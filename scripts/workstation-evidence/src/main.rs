//! Source-bound private workstation evidence. No command output enters public stdout.
mod receipt;
mod source_identity;

use receipt::{
    PHASES, SYSTEM, attribute, compare, coverage, read_receipt, sample, store, validate_receipt,
};
use serde_json::{Value as V, json};
use source_identity::{fingerprint, hash, root, source};
use std::{
    collections::BTreeMap,
    env,
    fs::{self, OpenOptions},
    io::{Read, Write},
    os::unix::{
        ffi::OsStrExt,
        fs::{OpenOptionsExt, PermissionsExt},
        process::{CommandExt, ExitStatusExt},
    },
    path::{Path, PathBuf},
    process::Command,
    sync::{Arc, Condvar, Mutex},
    time::{Duration, Instant},
};
use time::OffsetDateTime;
type R<T> = Result<T, Box<dyn std::error::Error>>;
static CANCELLED: std::sync::atomic::AtomicI32 = std::sync::atomic::AtomicI32::new(0);
fn fail<T>(message: &str) -> R<T> {
    Err(message.into())
}
fn require(ok: bool, message: &str) -> R<()> {
    if ok { Ok(()) } else { fail(message) }
}
fn now() -> String {
    let t = OffsetDateTime::now_utc();
    format!(
        "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}.{:09}+00:00",
        t.year(),
        u8::from(t.month()),
        t.day(),
        t.hour(),
        t.minute(),
        t.second(),
        t.nanosecond()
    )
}
fn text(v: &V) -> &str {
    v.as_str().unwrap_or("")
}
fn native() -> String {
    format!(
        "{}-{}",
        env::consts::ARCH.replace("arm64", "aarch64"),
        env::consts::OS.replace("macos", "darwin")
    )
}
fn hostname() -> String {
    nix::unistd::gethostname()
        .map(|x| x.to_string_lossy().into_owned())
        .unwrap_or_default()
}
fn group(pid: u32, sig: Option<nix::sys::signal::Signal>) -> bool {
    nix::sys::signal::killpg(nix::unistd::Pid::from_raw(pid as i32), sig).is_ok()
}
struct OwnedGroup(u32);
impl Drop for OwnedGroup {
    fn drop(&mut self) {
        group(self.0, Some(nix::sys::signal::Signal::SIGKILL));
    }
}
// Both verification and measurements use a single blocking child wait and a notified timer.
fn supervised(mut cmd: Command, timeout: f64) -> R<(std::process::ExitStatus, bool, bool)> {
    require(
        CANCELLED.load(std::sync::atomic::Ordering::SeqCst) == 0,
        "Execution cancelled",
    )?;
    require(
        timeout.is_finite() && timeout > 0.0 && timeout < u64::MAX as f64,
        "Timeout must be finite and positive",
    )?;
    let mut signals = signal_hook::iterator::Signals::new([
        signal_hook::consts::SIGINT,
        signal_hook::consts::SIGTERM,
        signal_hook::consts::SIGHUP,
    ])?;
    cmd.process_group(0);
    let mut child = cmd.spawn()?;
    let pid = child.id();
    let guard = OwnedGroup(pid);
    let state = Arc::new((Mutex::new(false), Condvar::new()));
    let shared = state.clone();
    let timer = std::thread::spawn(move || {
        let (lock, cv) = &*shared;
        let done = lock.lock().unwrap_or_else(|e| e.into_inner());
        let (done, wait) = cv
            .wait_timeout_while(done, Duration::from_secs_f64(timeout), |d| !*d)
            .unwrap_or_else(|e| e.into_inner());
        let expired = wait.timed_out() && !*done;
        if expired {
            group(pid, Some(nix::sys::signal::Signal::SIGKILL));
        }
        expired
    });
    let handle = signals.handle();
    let signal_thread = std::thread::spawn(move || {
        for signal in signals.forever() {
            CANCELLED.store(signal, std::sync::atomic::Ordering::SeqCst);
            group(pid, Some(nix::sys::signal::Signal::SIGKILL));
        }
    });
    let status = child.wait();
    {
        let (lock, cv) = &*state;
        *lock.lock().unwrap_or_else(|e| e.into_inner()) = true;
        cv.notify_one();
    }
    let expired = timer.join().map_err(|_| "timer failed")?;
    handle.close();
    signal_thread.join().map_err(|_| "signal observer failed")?;
    let descendants = group(pid, None);
    drop(guard);
    Ok((status?, expired, descendants))
}
#[derive(Debug)]
struct Verification {
    message: &'static str,
    stdout: String,
    stderr: String,
}
impl std::fmt::Display for Verification {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.message)
    }
}
impl std::error::Error for Verification {}
fn output(root: &Path, program: &str, args: &[&str], clean_git: bool) -> R<Vec<u8>> {
    let out = tempfile::tempfile()?;
    let err = tempfile::tempfile()?;
    let mut cmd = Command::new(program);
    cmd.args(args)
        .current_dir(root)
        .stdout(out.try_clone()?)
        .stderr(err.try_clone()?);
    if clean_git {
        for (k, _) in env::vars_os() {
            if k.as_bytes().starts_with(b"GIT_") {
                cmd.env_remove(k);
            }
        }
    }
    let (status, expired, descendants) = supervised(cmd, 120.0)?;
    use std::io::{Seek, SeekFrom};
    let mut out = out;
    out.seek(SeekFrom::Start(0))?;
    let mut bytes = Vec::new();
    out.read_to_end(&mut bytes)?;
    if expired || descendants || !status.success() {
        let mut err = err;
        err.seek(SeekFrom::Start(0))?;
        let mut stderr = Vec::new();
        err.take(65536).read_to_end(&mut stderr)?;
        return Err(Box::new(Verification {
            message: if expired {
                "Verification deadline exceeded"
            } else if descendants {
                "Candidate verification left background processes running"
            } else {
                "Verification command failed"
            },
            stdout: String::from_utf8_lossy(&bytes[..bytes.len().min(65536)]).into_owned(),
            stderr: String::from_utf8_lossy(&stderr).into_owned(),
        }));
    }
    Ok(bytes)
}
fn nix(root: &Path, args: &[&str]) -> R<String> {
    Ok(String::from_utf8(output(root, "nix", args, false)?)?
        .trim()
        .to_owned())
}
fn private(path: &Path, source: &Path) -> R<PathBuf> {
    let expanded = if let Ok(s) = path.strip_prefix("~") {
        PathBuf::from(env::var_os("HOME").ok_or("HOME unavailable")?).join(s)
    } else {
        path.to_owned()
    };
    // Resolve the existing ancestor before creating anything; never create inside source.
    let absolute = if expanded.is_absolute() {
        expanded
    } else {
        env::current_dir()?.join(expanded)
    };
    let mut ancestor = absolute.as_path();
    let mut tail = Vec::new();
    while !ancestor.exists() {
        tail.push(
            ancestor
                .file_name()
                .ok_or("invalid output path")?
                .to_owned(),
        );
        ancestor = ancestor.parent().ok_or("invalid output parent")?;
    }
    let mut resolved = ancestor.canonicalize()?;
    for item in tail.iter().rev() {
        resolved.push(item);
    }
    require(
        !resolved.starts_with(source),
        "Evidence must be stored outside the repository",
    )?;
    use std::os::unix::fs::DirBuilderExt;
    fs::DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(&resolved)?;
    let p = resolved.canonicalize()?;
    require(
        !p.starts_with(source),
        "Evidence must be stored outside the repository",
    )?;
    require(
        fs::metadata(&p)?.permissions().mode() & 0o077 == 0,
        "Evidence directory must be private, with mode 0700",
    )?;
    Ok(p)
}
fn write_json(path: &Path, v: &V) -> R<()> {
    let mut t = tempfile::NamedTempFile::new_in(path.parent().ok_or("missing parent")?)?;
    t.as_file()
        .set_permissions(fs::Permissions::from_mode(0o600))?;
    serde_json::to_writer_pretty(&mut t, v)?;
    t.write_all(b"\n")?;
    t.as_file().sync_all()?;
    fs::hard_link(t.path(), path)?;
    Ok(())
}
fn unique() -> R<String> {
    let t = OffsetDateTime::now_utc();
    let stamp = format!(
        "{:04}{:02}{:02}T{:02}{:02}{:02}",
        t.year(),
        u8::from(t.month()),
        t.day(),
        t.hour(),
        t.minute(),
        t.second()
    );
    Ok(format!(
        "{}-{}",
        stamp,
        tempfile::Builder::new()
            .prefix("")
            .tempfile()?
            .path()
            .file_name()
            .ok_or("temporary name missing")?
            .to_string_lossy()
    ))
}
fn config(root: &Path) -> V {
    match nix(root, &["config", "show", "--json"]).and_then(|s| Ok(serde_json::from_str::<V>(&s)?))
    {
        Ok(v) if v.as_object().is_some_and(|o| !o.is_empty()) => {
            json!({"status":"captured","sha256":fingerprint(&v)})
        }
        _ => {
            json!({"status":"unavailable","reason":"Empty, invalid or unavailable effective configuration"})
        }
    }
}
fn active() -> V {
    fs::canonicalize("/run/current-system")
        .map(|p| json!(p))
        .unwrap_or(V::Null)
}
fn runtime_matches(v: &V) -> bool {
    v.as_str().is_some_and(|s| {
        fs::canonicalize(s)
            .ok()
            .is_some_and(|p| active() == json!(p))
    })
}
fn environment(root: &Path, command: &[String]) -> R<String> {
    let cpu = fs::read_to_string("/proc/cpuinfo")
        .unwrap_or_default()
        .lines()
        .filter(|s| !s.starts_with("cpu MHz"))
        .collect::<Vec<_>>()
        .join("\n");
    let executable = command
        .first()
        .and_then(|c| {
            if c.contains('/') {
                PathBuf::from(c).canonicalize().ok()
            } else {
                env::split_paths(&env::var_os("PATH").unwrap_or_default())
                    .map(|p| p.join(c))
                    .find_map(|p| p.canonicalize().ok())
            }
        })
        .map(|p| {
            p.to_string_lossy()
                .replace(&*root.to_string_lossy(), "<SOURCE>")
        })
        .unwrap_or_default();
    let mut settings = BTreeMap::new();
    for k in ["NIX_CONFIG", "NIX_REMOTE", "NIX_PATH", "NIX_BUILD_HOOK"] {
        settings.insert(
            k,
            env::var(k)
                .unwrap_or_default()
                .replace(&*root.to_string_lossy(), "<SOURCE>"),
        );
    }
    let kernel = String::from_utf8(output(root, "uname", &["-r"], false)?)?
        .trim()
        .to_owned();
    Ok(fingerprint(
        &json!({"machine":hostname(),"kernel":kernel,"architecture":env::consts::ARCH,"cpu":cpu,"executable":executable,"nix_settings":settings}),
    ))
}
// A fresh process has no previously reaped children. RUSAGE_CHILDREN after one wait
// therefore provides that command's wait4 maximum and CPU totals without unsafe ABI code.
fn measurement_helper(args: &[String]) -> R<i32> {
    require(args.len() >= 5, "invalid private measurement protocol")?;
    let timeout = args[0].parse::<f64>()?;
    let root = Path::new(&args[1]);
    let log = Path::new(&args[2]);
    let receipt = Path::new(&args[3]);
    let source_root = root.canonicalize()?;
    let directory = private(log.parent().ok_or("Missing log directory")?, &source_root)?;
    require(
        receipt
            .parent()
            .is_some_and(|p| p.canonicalize().ok() == Some(directory.clone())),
        "Measurement receipt and log must share a private directory",
    )?;
    let out = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(log)?;
    let mut cmd = Command::new(&args[4]);
    cmd.args(&args[5..])
        .current_dir(root)
        .stdout(out.try_clone()?)
        .stderr(out);
    let start = Instant::now();
    let (status, expired, descendants) = supervised(cmd, timeout)?;
    let usage = nix::sys::resource::getrusage(nix::sys::resource::UsageWho::RUSAGE_CHILDREN)?;
    use nix::sys::time::TimeValLike;
    let rss = usage.max_rss() as f64
        / if cfg!(target_os = "macos") {
            1024.0
        } else {
            1.0
        };
    let code = status
        .code()
        .unwrap_or_else(|| -status.signal().unwrap_or(1));
    write_json(
        receipt,
        &json!({"exit_code":code,"timed_out":expired,"descendants_remained":descendants,"elapsed_seconds":start.elapsed().as_secs_f64(),"peak_rss_kib":rss,"user_seconds":usage.user_time().num_microseconds() as f64 /1e6,"system_seconds":usage.system_time().num_microseconds() as f64 /1e6}),
    )?;
    Ok(0)
}
fn measure(command: &[String], root: &Path, log: &Path, timeout: f64) -> R<V> {
    let result = log.with_extension("measurement.json");
    let mut signals = signal_hook::iterator::Signals::new([
        signal_hook::consts::SIGINT,
        signal_hook::consts::SIGTERM,
        signal_hook::consts::SIGHUP,
    ])?;
    let mut child = Command::new(env::current_exe()?)
        .arg("__measure")
        .arg(timeout.to_string())
        .arg(root)
        .arg(log)
        .arg(&result)
        .args(command)
        .spawn()?;
    let pid = nix::unistd::Pid::from_raw(child.id() as i32);
    let handle = signals.handle();
    let observer = std::thread::spawn(move || {
        for signal in signals.forever() {
            CANCELLED.store(signal, std::sync::atomic::Ordering::SeqCst);
            let _signal_result =
                nix::sys::signal::kill(pid, nix::sys::signal::Signal::try_from(signal).ok());
        }
    });
    let status = child.wait();
    handle.close();
    observer.join().map_err(|_| "signal observer failed")?;
    let status = status?;
    require(
        status.success(),
        "Could not start command or collect measurements",
    )?;
    let v = read(&result)?;
    fs::remove_file(result)?;
    Ok(v)
}
fn read(path: &Path) -> R<V> {
    Ok(serde_json::from_slice(&fs::read(path)?)?)
}
#[derive(Default)]
struct Args {
    source: PathBuf,
    policy: Option<PathBuf>,
    operation: String,
    values: BTreeMap<String, String>,
    command: Vec<String>,
    positionals: Vec<String>,
}
impl Args {
    fn get(&self, k: &str) -> &str {
        self.values.get(k).map(String::as_str).unwrap_or("")
    }
    fn runs(&self) -> R<u64> {
        Ok(self.get("runs").parse()?)
    }
    fn timeout(&self) -> R<f64> {
        Ok(self.get("timeout").parse()?)
    }
}
fn help(op: &str) {
    println!(
        "Record source-bound workstation checks and comparable command measurements.\n\nUsage: workstation-evidence [--source PATH] [--build-policy PATH] <source|run|benchmark|skip|compare|status>\n\nReports and command logs are private local evidence. Success records only the stated phase.\n\n{op}\nrun, benchmark: --output PATH --target TARGET --check CHECK --phase <evaluation|build|dry-activation|activation|runtime|recovery|vm> [--cache-condition <warm|cold|mixed|unspecified>] [--installable ATTR] [--build-receipt PATH] [--timeout SECONDS] [--runs N] -- COMMAND...\nskip: --output PATH --target TARGET --check CHECK --phase PHASE --reason TEXT [--system PLATFORM]\ncompare: BASELINE CANDIDATE --budget-percent PERCENT\nstatus: MANIFEST [RECORDS...]\n\n--source defaults to current directory; --output defaults to ~/.local/state/nix-conf/evidence. --timeout defaults to 7200 seconds. --runs defaults to 1 (benchmark: 3). --cache-condition defaults to unspecified."
    );
}
fn parse(argv: &[String]) -> R<Option<Args>> {
    let mut normalized = Vec::new();
    let mut operation = "";
    let mut value = false;
    let mut remainder = false;
    for arg in argv {
        if remainder {
            normalized.push(arg.clone());
            continue;
        }
        if value {
            normalized.push(arg.clone());
            value = false;
            continue;
        }
        if arg == "--" {
            remainder = true;
            normalized.push(arg.clone());
            continue;
        }
        if arg == "--help" || arg == "-h" {
            help(operation);
            return Ok(None);
        }
        if arg.starts_with("--") {
            if let Some((key, item)) = arg.split_once('=') {
                normalized.push(key.to_owned());
                normalized.push(item.to_owned());
            } else {
                normalized.push(arg.clone());
                value = true;
            }
        } else {
            normalized.push(arg.clone());
            if operation.is_empty() {
                operation = arg;
            } else if ["run", "benchmark"].contains(&operation) {
                remainder = true;
            }
        }
    }
    let argv = &normalized;
    let mut a = Args {
        source: env::current_dir()?,
        ..Default::default()
    };
    let mut i = 0;
    while i < argv.len() && argv[i].starts_with("--") {
        let k = &argv[i];
        require(
            ["--source", "--build-policy"].contains(&k.as_str()),
            "Unrecognized global option",
        )?;
        let v = argv.get(i + 1).ok_or("Missing option value")?;
        if k == "--source" {
            a.source = v.into();
        } else {
            a.policy = Some(v.into());
        }
        i += 2;
    }
    a.operation = argv.get(i).ok_or("Operation required")?.clone();
    i += 1;
    require(
        ["source", "run", "benchmark", "skip", "compare", "status"].contains(&a.operation.as_str()),
        "Unknown operation",
    )?;
    for (k, v) in [
        (
            "output",
            format!(
                "{}/.local/state/nix-conf/evidence",
                env::var("HOME").unwrap_or_default()
            ),
        ),
        ("cache-condition", "unspecified".into()),
        ("timeout", "7200".into()),
        (
            "runs",
            if a.operation == "benchmark" { "3" } else { "1" }.into(),
        ),
    ] {
        a.values.insert(k.into(), v);
    }
    while i < argv.len() {
        let s = &argv[i];
        if s == "--" {
            a.command = argv[i + 1..].to_vec();
            break;
        }
        if let Some(k) = s.strip_prefix("--") {
            let allowed = match a.operation.as_str() {
                "run" | "benchmark" => &[
                    "output",
                    "target",
                    "check",
                    "phase",
                    "cache-condition",
                    "installable",
                    "build-receipt",
                    "timeout",
                    "runs",
                ][..],
                "skip" => &[
                    "output",
                    "target",
                    "check",
                    "phase",
                    "cache-condition",
                    "reason",
                    "system",
                ][..],
                "compare" => &["budget-percent"][..],
                _ => &[],
            };
            require(allowed.contains(&k), "Unrecognized option")?;
            a.values.insert(
                k.into(),
                argv.get(i + 1).ok_or("Missing option value")?.clone(),
            );
            i += 2;
            continue;
        }
        if ["run", "benchmark"].contains(&a.operation.as_str()) {
            a.command = argv[i..].to_vec();
            break;
        }
        a.positionals.push(s.clone());
        i += 1;
    }
    if ["run", "benchmark", "skip"].contains(&a.operation.as_str()) {
        for k in ["target", "check", "phase"] {
            require(
                !a.get(k).is_empty(),
                "--target, --check and --phase are required",
            )?;
        }
        require(PHASES.contains(&a.get("phase")), "Invalid phase")?;
        require(
            ["warm", "cold", "mixed", "unspecified"].contains(&a.get("cache-condition")),
            "Invalid cache condition",
        )?;
        require(a.positionals.is_empty(), "Unexpected positional argument")?;
    }
    Ok(Some(a))
}
fn placement(a: &Args) -> R<()> {
    if a.get("phase") != "build" {
        return Ok(());
    }
    let Some(path) = &a.policy else { return Ok(()) };
    let policies = read(path)?;
    require(
        policies.is_object(),
        "Build placement policy must be an object",
    )?;
    let p = &policies[a.get("target")];
    if p.is_null() {
        return Ok(());
    }
    require(
        p.as_object()
            .is_some_and(|o| o.len() == 2 && o.contains_key("host") && o.contains_key("command"))
            && p["host"].as_str().is_some_and(|s| !s.is_empty()),
        "Build placement policy requires host and command",
    )?;
    let expected = p["command"]
        .as_array()
        .filter(|a| !a.is_empty() && a.iter().all(|s| s.as_str().is_some_and(|s| !s.is_empty())))
        .ok_or("Invalid build placement command")?;
    require(
        hostname().split('.').next() == p["host"].as_str(),
        &format!("Build {} on {}", a.get("target"), text(&p["host"])),
    )?;
    if a.get("check") == "full-system" {
        require(
            a.command.len() >= expected.len()
                && Path::new(&a.command[0])
                    .file_name()
                    .is_some_and(|n| n == text(&expected[0]))
                && expected[1..]
                    .iter()
                    .zip(&a.command[1..])
                    .all(|(x, y)| text(x) == y),
            "Record full-system builds with the policy command",
        )?;
    }
    Ok(())
}
fn candidate(a: &Args, r: &mut V) -> R<()> {
    if a.get("phase") == "build" {
        require(
            a.get("build-receipt").is_empty(),
            "A build cannot reuse another build receipt",
        )?;
        require(
            a.get("check") != "full-system" || !a.get("installable").is_empty(),
            "Full-system builds require --installable",
        )?;
        if !a.get("installable").is_empty() {
            require(
                attribute(&json!(a.get("installable"))),
                "Use a plain root output attribute for --installable",
            )?;
            let install = format!("{}#{}.outPath", a.source.display(), a.get("installable"));
            let output = nix(&a.source, &["eval", "--raw", &install])?;
            require(
                store(&json!(output)),
                "Candidate evaluation did not return a Nix store output",
            )?;
            r["system_path"] = json!(output);
            r["installable"] = json!(a.get("installable"));
        }
        return Ok(());
    }
    require(
        a.get("installable").is_empty(),
        "Use --installable only with a build",
    )?;
    if !SYSTEM.contains(&a.get("phase")) {
        require(
            a.get("build-receipt").is_empty(),
            "Build receipts are only used by system validation phases",
        )?;
        return Ok(());
    }
    require(
        !a.get("build-receipt").is_empty(),
        "System validation requires matching candidate build evidence",
    )?;
    let p = Path::new(a.get("build-receipt"));
    let built = read_receipt(p)?;
    require(
        built["status"] == "passed"
            && built["phase"] == "build"
            && built["source"] == r["source"]
            && built["target"] == r["target"]
            && built["system"] == native()
            && attribute(&built["installable"]),
        "Build receipt must prove this source, target and native system",
    )?;
    r["system_path"] = built["system_path"].clone();
    r["installable"] = built["installable"].clone();
    r["build_receipt_sha256"] = json!(hash(&fs::read(p)?));
    Ok(())
}
fn execute(a: &Args, out: &Path, id: &str, r: &mut V) -> R<()> {
    candidate(a, r)?;
    let phase = a.get("phase");
    let system = SYSTEM.contains(&phase);
    let runtime = ["runtime", "recovery"].contains(&phase);
    if system {
        r["active_system_before"] = active();
    }
    if runtime {
        require(
            runtime_matches(&r["system_path"]),
            "The specified built system is not the active generation",
        )?;
    }
    for trial in 0..a.runs()? {
        let log = format!("{id}-{}.log", trial + 1);
        match measure(&a.command, &a.source, &out.join(&log), a.timeout()?) {
            Ok(mut m) => {
                m["log"] = json!(log);
                let passed = sample(&m, true);
                r["measurements"]
                    .as_array_mut()
                    .ok_or("missing samples")?
                    .push(m);
                if !passed {
                    break;
                }
            }
            Err(_) => {
                r["reason"] = json!("Could not start command or collect measurements");
                break;
            }
        }
    }
    if system {
        r["active_system_after"] = active();
    }
    if CANCELLED.load(std::sync::atomic::Ordering::SeqCst) != 0 {
        r["reason"] = json!("Command cancelled");
        return Ok(());
    }
    let samples = r["measurements"].as_array().ok_or("missing samples")?;
    let success = samples.len() as u64 == a.runs()? && samples.iter().all(|s| sample(s, true));
    if phase == "build" && !r["system_path"].is_null() && success {
        nix(&a.source, &["path-info", text(&r["system_path"])])?;
    }
    let after = config(&a.source);
    if r["nix_configuration"] != after {
        r["nix_configuration_after"] = after;
        return fail(
            "Effective Nix client configuration changed or could not be compared across execution",
        );
    }
    let after = source(&a.source)?;
    if r["source"] != after {
        r["source_after"] = after;
        return fail("Tracked source changed during execution");
    }
    if runtime || phase == "activation" {
        require(
            runtime_matches(&r["system_path"]),
            "Active generation does not match the candidate after execution",
        )?;
    }
    if phase == "dry-activation" {
        require(
            r["active_system_before"] == r["active_system_after"],
            "Dry activation changed the active system generation",
        )?;
    }
    if success && r.get("reason").is_none() {
        r["status"] = json!("passed");
    } else if r.get("reason").is_none() {
        r["reason"] = json!("Command failed, timed out or left background work running");
    }
    Ok(())
}
fn capture(a: &Args) -> R<i32> {
    let out = private(Path::new(a.get("output")), &a.source)?;
    let skip = a.operation == "skip";
    if skip {
        require(
            !a.get("reason").trim().is_empty(),
            "A skipped check requires a reason",
        )?;
    } else {
        require(!a.command.is_empty(), "Provide a command after --")?;
        placement(a)?;
    }
    let id = unique()?;
    let path = out.join(format!("{id}.json"));
    let command = if skip { vec![] } else { a.command.clone() };
    let runs = a.runs()?;
    let mut r = json!({"schema":1,"kind":if runs>1{"benchmark"}else{"check"},"date":now(),"target":a.get("target"),"check":a.get("check"),"phase":a.get("phase"),"system":if a.get("system").is_empty(){native()}else{a.get("system").into()},"source":source(&a.source)?,"cache_condition":a.get("cache-condition"),"environment_sha256":environment(&a.source,&command)?,"nix_configuration":config(&a.source),"expected_runs":runs,"system_path":null,"installable":null,"build_receipt_sha256":null,"active_system_before":null,"active_system_after":null,"command_sha256":fingerprint(&json!(command.iter().map(|c|c.replace(&*a.source.to_string_lossy(),"<SOURCE>")).collect::<Vec<_>>().clone())),"measurements":[],"status":"failed","limitations":["Peak RSS is wait4 maximum, not aggregate process-tree memory.","Cache condition is an operator declaration; this command does not clear caches.","Resource measurements exclude Nix daemon and remote builder usage.","Effective Nix configuration describes the client; daemon and remote settings remain outside this observation.","Candidate evaluation and realization checks each have a separate 120-second timeout.","Commands must finish synchronously; processes that create another session escape group cleanup.","Source and active-generation checks observe endpoints, not transient changes during execution."]});
    if skip {
        r["status"] = json!("skipped");
        r["reason"] = json!(a.get("reason"));
    } else if let Err(e) = execute(a, &out, &id, &mut r) {
        if let Some(verification) = e.downcast_ref::<Verification>() {
            r["status"] = json!("failed");
            r["reason"] = json!(verification.message);
            let name = format!("{id}-verification.json");
            write_json(
                &out.join(&name),
                &json!({"exception":"VerificationError","message":verification.message,"stdout":verification.stdout,"stderr":verification.stderr}),
            )?;
            r["verification_log"] = json!(name);
        } else {
            r["status"] = json!("invalid");
            r["reason"] = json!(e.to_string());
        }
    }
    r["finished"] = json!(now());
    validate_receipt(&r)?;
    write_json(&path, &r)?;
    println!("{}", path.display());
    Ok(if r["status"] == "passed" { 0 } else { 1 })
}
fn dispatch(mut a: Args) -> R<i32> {
    if a.operation != "compare" {
        a.source = root(&a.source)?;
    }
    let result = match a.operation.as_str() {
        "source" => {
            require(a.positionals.is_empty(), "Unexpected positional argument")?;
            source(&a.source)?
        }
        "run" | "benchmark" => {
            require(a.runs()? > 0, "Runs and timeout must be positive")?;
            let t = a.timeout()?;
            require(
                t.is_finite() && t > 0.0 && t < u64::MAX as f64,
                "Runs and timeout must be positive and representable",
            )?;
            return capture(&a);
        }
        "skip" => return capture(&a),
        "compare" => {
            require(
                a.positionals.len() == 2,
                "Provide baseline and candidate receipts",
            )?;
            let budget = a.get("budget-percent").parse::<f64>()?;
            compare(
                &read_receipt(Path::new(&a.positionals[0]))?,
                &read_receipt(Path::new(&a.positionals[1]))?,
                budget,
            )?
        }
        "status" => {
            require(!a.positionals.is_empty(), "Provide a manifest")?;
            let records = a.positionals[1..]
                .iter()
                .map(|p| read_receipt(Path::new(p)))
                .collect::<R<Vec<_>>>()?;
            coverage(&a.source, &read(Path::new(&a.positionals[0]))?, &records)?
        }
        _ => return fail("Unknown operation"),
    };
    println!("{}", serde_json::to_string_pretty(&result)?);
    Ok(if result.get("status").is_none_or(|s| s == "passed") {
        0
    } else {
        1
    })
}
fn main() {
    let args = env::args().skip(1).collect::<Vec<_>>();
    let result = if args.first().is_some_and(|s| s == "__measure") {
        measurement_helper(&args[1..])
    } else {
        parse(&args).and_then(|a| a.map(dispatch).unwrap_or(Ok(0)))
    };
    let cancelled = CANCELLED.load(std::sync::atomic::Ordering::SeqCst);
    if cancelled != 0 && !args.first().is_some_and(|s| s == "__measure") {
        std::process::exit(128 + cancelled);
    }
    match result {
        Ok(code) => std::process::exit(code),
        Err(e) => {
            eprintln!("error: {e}");
            std::process::exit(2)
        }
    }
}
