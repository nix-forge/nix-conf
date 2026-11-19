//! Source-bound Mac workflows. The remote host must have a trusted native
//! mac-source package. Exported source is never executed as a verifier.
mod receipt;
mod snapshot;

use fs2::FileExt;
use receipt::{finish_report, lock, private_dir, save};
use serde_json::{Value, json};
use snapshot::{encoded, freshness, snapshot, verify};
use std::{
    collections::BTreeMap,
    env,
    error::Error,
    fs::{self, OpenOptions},
    io::Write,
    os::unix::{
        fs::{OpenOptionsExt, PermissionsExt},
        process::{CommandExt, ExitStatusExt},
    },
    path::{Path, PathBuf},
    process::{Command, ExitStatus, Stdio},
};
type Result<T> = std::result::Result<T, Box<dyn Error>>;
const REMOTE_VERIFIER: &str = r#"
verifier=$(command -v mac-source) || verifier="$HOME/.local/state/nix-conf/mac-verifier/bin/mac-source"
if [ ! -x "$verifier" ]; then
    printf '%s\n' 'Install a trusted native mac-source verifier on this Mac before exporting.' >&2
    exit 127
fi
exec "$verifier" "#;
fn fail<T>(message: impl Into<String>) -> Result<T> {
    Err(message.into().into())
}
fn string<'a>(v: &'a Value, key: &str) -> Result<&'a str> {
    v.get(key)
        .and_then(Value::as_str)
        .ok_or_else(|| format!("Missing string: {key}").into())
}
fn strings(v: &Value) -> Result<Vec<String>> {
    v.as_array()
        .ok_or("Require an argument array")?
        .iter()
        .map(|v| {
            v.as_str()
                .map(String::from)
                .ok_or_else(|| "Require string arguments".into())
        })
        .collect()
}
fn status(s: ExitStatus) -> i32 {
    s.code().unwrap_or_else(|| 128 + s.signal().unwrap_or(1))
}
fn capture(args: &[&str], cwd: Option<&Path>) -> Result<Vec<u8>> {
    let mut c = Command::new(args.first().ok_or("Empty command")?);
    c.args(&args[1..]).stderr(Stdio::inherit());
    if let Some(p) = cwd {
        c.current_dir(p);
    }
    let o = c.output()?;
    if !o.status.success() {
        return fail(format!("{} failed ({})", args[0], status(o.status)));
    }
    Ok(o.stdout)
}
fn text(args: &[&str], cwd: Option<&Path>) -> Result<String> {
    Ok(String::from_utf8(capture(args, cwd)?)?.trim().into())
}
// O_NOFOLLOW is obtained through the safe rustix flag API, never a libc bridge.
fn rustix_no_follow() -> i32 {
    rustix::fs::OFlags::NOFOLLOW.bits() as i32
}
fn valid_host(host: &str) -> bool {
    !host.is_empty()
        && !host.starts_with('-')
        && host
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"_@.-".contains(&b))
}
fn store_path(path: &str) -> bool {
    Path::new(path).parent() == Some(Path::new("/nix/store"))
        && Path::new(path).file_name().is_some()
}
fn remote(v: &Value, arguments: &[String]) -> Result<i32> {
    let host = string(v, "host")?;
    if !valid_host(host) {
        return fail("Require an SSH host alias");
    }
    let mut args = arguments.to_vec();
    args.extend([
        "--snapshot".into(),
        string(v, "snapshot")?.into(),
        "--expected".into(),
        string(v, "identity")?.into(),
    ]);
    let quoted_arguments = args
        .iter()
        .map(|s| shell_words::quote(s).into_owned())
        .collect::<Vec<_>>()
        .join(" ");
    let command = format!("{REMOTE_VERIFIER}{quoted_arguments}");
    let code = status(Command::new("ssh").args(["--", host, &command]).status()?);
    if code != 0 && arguments == ["_verify"] {
        return fail("Remote snapshot verification failed; no export receipt published");
    }
    Ok(code)
}
fn export(
    source: &str,
    host: &str,
    receipt: &Path,
    includes: &[String],
    quiet: bool,
) -> Result<()> {
    if !valid_host(host) {
        return fail("Require an SSH host alias");
    }
    let source = fs::canonicalize(source)?;
    let receipt = std::path::absolute(receipt)?;
    let parent = receipt.parent().ok_or("Missing receipt parent")?;
    private_dir(parent)?;
    let lock_path = PathBuf::from(format!("{}.lock", receipt.display()));
    let _lock = lock(&lock_path)?;
    if fs::symlink_metadata(&receipt).is_ok() {
        return fail("Receipt already exists; choose a new receipt for each export");
    }
    let temp = tempfile::Builder::new().prefix("mac-export-").tempdir()?;
    let dest = temp.path().join("source");
    let identity = snapshot(&source, &dest, includes)?;
    let store = text(
        &[
            "nix",
            "store",
            "add-path",
            "--name",
            "mac-source",
            dest.to_str().ok_or("Invalid path")?,
        ],
        None,
    )?;
    if !store_path(&store) {
        return fail("Nix did not return an immutable store source");
    }
    verify(Path::new(&store), &identity)?;
    let value = json!({"schema":1,"source":source,"host":host,"snapshot":store,"identity":identity,"includes":includes});
    let anchor = format!("{}.source", receipt.display());
    // A failed transfer leaves the owned GC root for diagnosis/retry; never clobber it.
    if fs::symlink_metadata(&anchor).is_ok() {
        return fail("Receipt GC root already exists; choose a new receipt");
    }
    capture(
        &[
            "nix-store",
            "--add-root",
            &anchor,
            "--indirect",
            "-r",
            &store,
        ],
        None,
    )?;
    capture(
        &["nix", "copy", "--to", &format!("ssh://{host}"), &store],
        None,
    )?;
    remote(&value, &["_verify".into()])?;
    freshness(&value)?;
    save(&receipt, &value, true)?;
    if quiet {
        eprintln!("{}", receipt.display());
    } else {
        println!("{}", receipt.display());
    }
    Ok(())
}
fn program_offset(command: &[String]) -> usize {
    if command
        .first()
        .is_some_and(|v| Path::new(v).file_name().is_some_and(|n| n == "env"))
    {
        1 + command[1..].iter().take_while(|s| s.contains('=')).count()
    } else {
        0
    }
}
fn nix_indices(p: &[String]) -> Result<Vec<usize>> {
    let switches = [
        "--no-link",
        "--no-write-lock-file",
        "--no-update-lock-file",
        "--impure",
        "--json",
        "--raw",
        "--show-trace",
        "--print-out-paths",
        "--print-build-logs",
        "-L",
        "--keep-going",
        "-k",
        "--keep-failed",
        "-K",
        "--offline",
        "--refresh",
        "--rebuild",
        "--verbose",
        "-v",
        "--quiet",
        "-q",
        "--accept-flake-config",
        "--no-accept-flake-config",
        "--all-systems",
        "--no-build",
    ];
    let values = [
        "--max-jobs",
        "--cores",
        "--out-link",
        "-o",
        "--log-format",
        "--extra-experimental-features",
        "--experimental-features",
    ];
    let mut i = if p.get(1).is_some_and(|s| s == "flake")
        && p.get(2)
            .is_some_and(|s| ["check", "metadata", "archive"].contains(&s.as_str()))
    {
        3
    } else if p
        .get(1)
        .is_some_and(|s| ["build", "eval", "develop"].contains(&s.as_str()))
    {
        2
    } else {
        return fail(
            "Nix source verification supports build, eval, develop and flake check/metadata/archive",
        );
    };
    let mut out = vec![];
    while i < p.len() {
        let arg = &p[i];
        if p[1] == "develop" && ["--command", "-c"].contains(&arg.as_str()) {
            break;
        }
        if arg.starts_with('-') {
            let (flag, inline) = arg
                .split_once('=')
                .map_or((arg.as_str(), false), |(k, _)| (k, true));
            let arity = if switches.contains(&flag) {
                0
            } else if values.contains(&flag) {
                1
            } else if flag == "--option" {
                2
            } else {
                return fail(format!(
                    "Nix source override or unsupported option: {flag}; use a snapshot installable"
                ));
            };
            if inline && arity == 0 {
                return fail(format!("Unsupported value for Nix switch: {flag}"));
            }
            let count = arity - usize::from(inline);
            if i + count >= p.len() {
                return fail(format!("Missing Nix option value: {flag}"));
            }
            i += 1 + count;
        } else {
            out.push(i);
            i += 1;
        }
    }
    Ok(out)
}
fn source_command(root: &Path, command: &[String]) -> Result<Vec<String>> {
    let offset = program_offset(command);
    let p = &command[offset..];
    if !p
        .first()
        .is_some_and(|s| Path::new(s).file_name().is_some_and(|n| n == "nix"))
    {
        return Ok(command.to_vec());
    }
    let root = fs::canonicalize(root)?;
    let mut out = command.to_vec();
    for i in nix_indices(p)? {
        let arg = &p[i];
        let arg_no_path = arg.strip_prefix("path:").unwrap_or(arg);
        let (candidate, fragment) = arg_no_path
            .split_once('#')
            .map_or((arg_no_path, None), |(a, b)| (a, Some(b)));
        let explicit = arg.starts_with("path:")
            || candidate.starts_with('/')
            || candidate.starts_with("./")
            || candidate.starts_with("../")
            || candidate == "."
            || candidate == "..";
        if !explicit {
            return fail(
                "Nix source is outside the verified snapshot or uses a registry; use . or {source}",
            );
        }
        let resolved = fs::canonicalize(root.join(candidate))?;
        if resolved != root {
            return fail("Nix installables must select the verified snapshot root; use .#target");
        }
        out[offset + i] = format!(".{}", fragment.map(|f| format!("#{f}")).unwrap_or_default());
    }
    Ok(out)
}
fn execute_verified(root: &Path, expected: &str, command: &[String]) -> Result<i32> {
    let command = source_command(root, command)?;
    let first = command
        .first()
        .ok_or("Require a build or test command after --")?;
    verify(root, expected)?;
    let result = Command::new(first)
        .args(&command[1..])
        .current_dir(root)
        .env("MAC_SOURCE_ROOT", root)
        .env("MAC_SOURCE_IDENTITY", expected)
        .status();
    verify(root, expected)?;
    Ok(status(result?))
}
fn remote_dispatch(
    mode: &str,
    snapshot: &str,
    expected: &str,
    command: Option<&str>,
) -> Result<i32> {
    if env::consts::OS != "macos" {
        return fail("Remote Mac source commands require Darwin");
    }
    if !store_path(snapshot) {
        return fail("Remote commands require an immutable Nix store snapshot");
    }
    if expected.len() != 64
        || !expected
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    {
        return fail("Require a SHA-256 snapshot identity");
    }
    let root = Path::new(snapshot);
    let roots = PathBuf::from(env::var("HOME")?).join(".local/state/nix-conf/mac-sources");
    private_dir(&roots)?;
    {
        let _lock = lock(&roots.join(".lock"))?;
        let anchor = roots.join(expected);
        if fs::symlink_metadata(&anchor).is_ok() {
            if !anchor.is_symlink() || fs::canonicalize(&anchor)? != root {
                return fail("Remote GC root conflicts with this snapshot");
            }
        } else {
            capture(
                &[
                    "nix-store",
                    "--add-root",
                    anchor.to_str().ok_or("Invalid root")?,
                    "--indirect",
                    "-r",
                    snapshot,
                ],
                None,
            )?;
        }
    }
    if mode == "_run" {
        let c = strings(&serde_json::from_str(
            command.ok_or("Missing command JSON")?,
        )?)?
        .into_iter()
        .map(|s| s.replace("{source}", snapshot))
        .collect::<Vec<_>>();
        execute_verified(root, expected, &c)
    } else {
        verify(root, expected)?;
        Ok(0)
    }
}
fn run(receipt: &str, command: &[String]) -> Result<i32> {
    if command.is_empty() {
        return fail("Require a build or test command after --");
    }
    let _lock = lock(Path::new(&format!("{receipt}.lock")))?;
    let v: Value = serde_json::from_slice(&fs::read(receipt)?)?;
    let path = PathBuf::from(format!("{receipt}.last-run.json"));
    let mut report =
        json!({"identity":v["identity"],"command":command,"status":"validating","exitCode":1});
    save(&path, &report, false)?;
    let result = (|| {
        freshness(&v)?;
        let code = remote(
            &v,
            &[
                "_run".into(),
                "--command-json".into(),
                serde_json::to_string(command)?,
            ],
        )?;
        freshness(&v)?;
        Ok(code)
    })();
    finish_report(&path, &mut report, &result)?;
    result
}
fn deploy_arguments(arguments: &[String]) -> Result<(Vec<String>, Vec<String>)> {
    let switches = [
        "--dry-activate",
        "--debug-logs",
        "-d",
        "--no-progress",
        "--no-demarcate-output",
        "--keep-result",
        "-k",
        "--skip-checks",
        "-s",
        "--remote-build",
        "--boot",
        "--test",
        "--checksigs",
        "-c",
        "--interactive",
        "-i",
    ];
    let values = [
        "--log-dir",
        "--result-path",
        "-r",
        "--fast-connection",
        "--auto-rollback",
        "--magic-rollback",
        "--confirm-timeout",
        "--activation-timeout",
        "--temp-path",
        "--rollback-succeeded",
        "--sudo",
        "--interactive-sudo",
    ];
    let mut flags = vec![];
    let mut i = 0;
    while i < arguments.len() && arguments[i] != "--" {
        let arg = &arguments[i];
        let flag = arg.split('=').next().ok_or("Missing option")?;
        if !switches.contains(&flag) && !values.contains(&flag) {
            return fail(format!(
                "Unsupported deploy option or target override: {arg}"
            ));
        }
        flags.push(arg.clone());
        if values.contains(&flag) && !arg.contains('=') {
            i += 1;
            flags.push(
                arguments
                    .get(i)
                    .ok_or_else(|| format!("Missing deploy option value: {flag}"))?
                    .clone(),
            );
        }
        i += 1;
    }
    let extra = arguments.get(i + 1..).unwrap_or_default().to_vec();
    let mut p = vec!["nix".into(), "build".into()];
    p.extend_from_slice(&extra);
    if !nix_indices(&p)?.is_empty() {
        return fail("Extra build arguments cannot select a different source");
    }
    Ok((flags, extra))
}
fn option_values(arguments: &[String], names: &[&str]) -> Result<Vec<String>> {
    let mut values = vec![];
    for (i, arg) in arguments.iter().enumerate() {
        let (name, value) = arg
            .split_once('=')
            .map_or((arg.as_str(), None), |(a, b)| (a, Some(b)));
        if names.contains(&name) {
            values.push(
                value
                    .map(String::from)
                    .or_else(|| arguments.get(i + 1).cloned())
                    .ok_or_else(|| format!("Missing Nix option value: {name}"))?,
            );
        }
    }
    Ok(values)
}
fn client_command(
    arguments: &[String],
    real: &str,
    store: &str,
    checksigs: bool,
) -> Result<Vec<String>> {
    let stores = option_values(arguments, &["--store"])?;
    if stores.iter().any(|s| s != store) {
        return fail("Deploy-rs attempted to use a store outside the verified Mac");
    }
    if arguments.first().is_some_and(|s| s == "build")
        && !stores.is_empty()
        && !arguments.iter().any(|s| {
            let s = s.strip_suffix("^out").unwrap_or(s);
            store_path(s) && s.ends_with(".drv")
        })
    {
        return fail("Remote build must consume the already evaluated deployment derivation");
    }
    let mut command = vec![real.to_string()];
    if arguments.first().is_some_and(|s| s == "copy") {
        if option_values(arguments, &["--to", "-t"])? != [store] {
            return fail("Deploy-rs attempted to copy outside the verified Mac");
        }
        if !checksigs {
            command.extend(["copy".into(), "--no-check-sigs".into()]);
            command.extend_from_slice(&arguments[1..]);
            return Ok(command);
        }
    }
    command.extend_from_slice(arguments);
    Ok(command)
}
fn client_nix(arguments: &[String]) -> Result<i32> {
    let command = client_command(
        arguments,
        &env::var("MAC_DEPLOY_NIX")?,
        &env::var("MAC_DEPLOY_STORE")?,
        env::var("MAC_DEPLOY_CHECKSIGS")? == "1",
    )?;
    let mut log = OpenOptions::new()
        .create(true)
        .append(true)
        .mode(0o600)
        .custom_flags(rustix_no_follow())
        .open(env::var("MAC_DEPLOY_LOG")?)?;
    log.lock_exclusive()?;
    log.write_all(&encoded(&json!({"argv":arguments}))?)?;
    log.write_all(b"\n")?;
    FileExt::unlock(&log)?;
    Err(Command::new(&command[0]).args(&command[1..]).exec().into())
}
fn find_nix() -> Result<PathBuf> {
    for dir in env::split_paths(&env::var_os("PATH").ok_or("PATH unavailable")?) {
        let p = dir.join("nix");
        if p.is_file() && fs::metadata(&p)?.permissions().mode() & 0o111 != 0 {
            return Ok(fs::canonicalize(p)?);
        }
    }
    fail("Nix is unavailable for deployment")
}
fn run_client(v: &Value, command: &[String], checksigs: bool) -> Result<i32> {
    let real = find_nix()?;
    let client_root = Path::new(string(v, "clientRoot")?);
    let dir = tempfile::Builder::new()
        .prefix(".deploy-tools-")
        .tempdir_in(client_root.parent().ok_or("Missing client parent")?)?;
    let shim = dir.path().join("nix");
    let exe = env::current_exe()?;
    fs::write(
        &shim,
        format!(
            "#!/bin/sh\nexec {} _client-nix -- \"$@\"\n",
            shell_words::quote(exe.to_str().ok_or("Invalid executable path")?)
        ),
    )?;
    fs::set_permissions(&shim, fs::Permissions::from_mode(0o700))?;
    let mut paths = vec![dir.path().to_path_buf()];
    paths.extend(env::split_paths(
        &env::var_os("PATH").ok_or("PATH unavailable")?,
    ));
    Ok(status(
        Command::new(command.first().ok_or("Empty deploy command")?)
            .args(&command[1..])
            .env("PATH", env::join_paths(paths)?)
            .env("MAC_DEPLOY_NIX", real)
            .env(
                "MAC_DEPLOY_STORE",
                format!("ssh-ng://root@{}", string(v, "host")?),
            )
            .env(
                "MAC_DEPLOY_LOG",
                format!("{}.nix.jsonl", client_root.display()),
            )
            .env("MAC_DEPLOY_CHECKSIGS", if checksigs { "1" } else { "0" })
            .status()?,
    ))
}
fn deploy_operation(
    v: &Value,
    configuration: &str,
    kind: &str,
    flags: &[String],
    extra: &[String],
) -> Result<i32> {
    freshness(v)?;
    let root = Path::new(string(v, "snapshot")?);
    let identity = string(v, "identity")?;
    verify(root, identity)?;
    remote(v, &["_verify".into()])?;
    let reference = format!("path:{}", root.display());
    eprintln!("Preparing deploy-rs for the verified snapshot...");
    let meta: Value = serde_json::from_slice(&capture(
        &[
            "nix",
            "eval",
            "--accept-flake-config",
            "--json",
            "--no-write-lock-file",
            &format!("{reference}#deploy.nodes.{configuration}"),
            "--apply",
            "node: { inherit (node) hostname; profileUser = node.profiles.system.user or null; }",
        ],
        None,
    )?)?;
    if meta["hostname"] != v["host"] || meta["profileUser"] != "root" {
        return fail("Deploy system profile must use the verified Mac hostname and root account");
    }
    let outputs: Value = serde_json::from_slice(&capture(
        &[
            "nix",
            "build",
            "--accept-flake-config",
            "--json",
            "--out-link",
            string(v, "clientRoot")?,
            "--no-write-lock-file",
            "--max-jobs",
            "1",
            "--cores",
            "2",
            &format!("{reference}#deploy-rs"),
        ],
        None,
    )?)?;
    let out = outputs
        .as_array()
        .filter(|o| o.len() == 1)
        .and_then(|o| o[0]["outputs"].as_object())
        .filter(|o| o.len() == 1)
        .and_then(|o| o.get("out"))
        .and_then(Value::as_str)
        .ok_or("Require exactly one deployment client output")?;
    if !store_path(out) {
        return fail("Deployment client must come from the immutable Nix store");
    }
    freshness(v)?;
    remote(v, &["_verify".into()])?;
    let mut command = vec![format!("{out}/bin/deploy"), "--skip-checks".into()];
    if kind == "build" {
        command.push("--dry-activate".into());
    }
    command.extend_from_slice(flags);
    command.extend(
        [
            "--remote-build",
            "--ssh-user",
            "root",
            "--profile-user",
            "root",
            "--hostname",
            string(v, "host")?,
            "--ssh-opts",
            "",
            &format!("{reference}#{configuration}.system"),
            "--",
            "--max-jobs",
            "2",
            "--cores",
            "4",
            "--no-write-lock-file",
        ]
        .map(String::from),
    );
    command.extend_from_slice(extra);
    let result = run_client(
        v,
        &command,
        flags
            .iter()
            .any(|f| ["--checksigs", "-c"].contains(&f.as_str())),
    )?;
    remote(v, &["_verify".into()])?;
    verify(root, identity)?;
    freshness(v)?;
    Ok(result)
}
fn deploy(receipt: &str, configuration: &str, kind: &str, arguments: &[String]) -> Result<i32> {
    if configuration.is_empty()
        || !configuration
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"_-".contains(&b))
    {
        return fail("Require a configured Darwin node name");
    }
    let (flags, extra) = deploy_arguments(arguments)?;
    let _lock = lock(Path::new(&format!("{receipt}.lock")))?;
    let mut v: Value = serde_json::from_slice(&fs::read(receipt)?)?;
    v["clientRoot"] = json!(format!("{receipt}.client"));
    let path = PathBuf::from(format!("{receipt}.last-run.json"));
    let mut report = json!({"identity":v["identity"],"kind":kind,"configuration":configuration,"arguments":arguments,"clientRoot":v["clientRoot"],"status":"validating","exitCode":1});
    save(&path, &report, false)?;
    let result = deploy_operation(&v, configuration, kind, &flags, &extra);
    finish_report(&path, &mut report, &result)?;
    result
}
struct Args {
    mode: String,
    options: BTreeMap<String, Vec<String>>,
    command: Vec<String>,
}
fn parse() -> Result<Args> {
    let mut args = env::args().skip(1);
    let mode = args
        .next()
        .ok_or("Require export, auto, run, _verify, _run or _client-nix")?;
    if ["--help", "-h"].contains(&mode.as_str()) {
        return Ok(Args {
            mode: "help".into(),
            options: BTreeMap::new(),
            command: vec![],
        });
    }
    let allowed: &[&str] = match mode.as_str() {
        "export" => &["--source", "--host", "--receipt", "--include"],
        "auto" => &["--source", "--host", "--kind", "--configuration"],
        "run" => &["--receipt"],
        "_verify" => &["--snapshot", "--expected"],
        "_run" => &["--snapshot", "--expected", "--command-json"],
        "_client-nix" => &[],
        _ => return fail("Unknown mac-source mode"),
    };
    let mut options: BTreeMap<String, Vec<String>> = BTreeMap::new();
    let mut command = vec![];
    while let Some(arg) = args.next() {
        if ["--help", "-h"].contains(&arg.as_str()) {
            return Ok(Args {
                mode: "help".into(),
                options,
                command,
            });
        }
        if arg == "--" {
            command.extend(args);
            break;
        }
        if !arg.starts_with('-') && ["run", "auto", "_client-nix"].contains(&mode.as_str()) {
            command.push(arg);
            command.extend(args);
            break;
        }
        let (key, value) = if let Some((a, b)) = arg.split_once('=') {
            (a.to_string(), b.to_string())
        } else {
            (arg, args.next().ok_or("Missing option value")?)
        };
        if !allowed.contains(&key.as_str()) {
            return fail(format!("Unknown option: {key}"));
        }
        options.entry(key).or_default().push(value);
    }
    if !command.is_empty() && !["run", "auto", "_client-nix"].contains(&mode.as_str()) {
        return fail("Unexpected positional arguments");
    }
    let required: &[&str] = match mode.as_str() {
        "export" | "run" => &["--receipt"],
        "auto" => &["--kind"],
        "_verify" => &["--snapshot", "--expected"],
        "_run" => &["--snapshot", "--expected", "--command-json"],
        _ => &[],
    };
    for key in required {
        if !options.contains_key(*key) {
            return fail(format!("Required option: {key}"));
        }
    }
    if mode == "auto"
        && !options
            .get("--kind")
            .and_then(|v| v.last())
            .is_some_and(|k| ["command", "check", "test", "build", "deploy"].contains(&k.as_str()))
    {
        return fail("Invalid auto kind");
    }
    Ok(Args {
        mode,
        options,
        command,
    })
}
impl Args {
    fn get(&self, key: &str, default: &str) -> String {
        self.options
            .get(key)
            .and_then(|s| s.last())
            .map_or_else(|| default.into(), Clone::clone)
    }
    fn need(&self, key: &str) -> Result<String> {
        self.options
            .get(key)
            .and_then(|s| s.last())
            .cloned()
            .ok_or_else(|| format!("Required option: {key}").into())
    }
}
fn dispatch(a: Args) -> Result<i32> {
    match a.mode.as_str() {
        "help" => {
            println!(
                "mac-source: export complete Git working trees and run Mac commands against verified snapshots.\n\nexport [--source .] [--host macbook] --receipt PATH [--include PATH]...\nrun --receipt PATH -- COMMAND...\nauto [--source .] [--host macbook] --kind command|check|test|build|deploy [--configuration macbook-pro-m4] -- ARGS...\n_verify --snapshot PATH --expected SHA256\n_run --snapshot PATH --expected SHA256 --command-json JSON\n_client-nix -- ARGS..."
            );
            Ok(0)
        }
        "export" => {
            export(
                &a.get("--source", "."),
                &a.get("--host", "macbook"),
                Path::new(&a.need("--receipt")?),
                a.options.get("--include").map_or(&[], Vec::as_slice),
                false,
            )?;
            Ok(0)
        }
        "run" => run(&a.need("--receipt")?, &a.command),
        "_client-nix" => client_nix(&a.command),
        "auto" => {
            let kind = a.need("--kind")?;
            if !["command", "check", "test", "build", "deploy"].contains(&kind.as_str()) {
                return fail("Invalid auto kind");
            }
            let state = env::var_os("XDG_STATE_HOME")
                .map(PathBuf::from)
                .unwrap_or(PathBuf::from(env::var("HOME")?).join(".local/state"))
                .join("nix-conf/mac-source-runs");
            private_dir(&state)?;
            // Keep receipts and GC roots after the command, including failures.
            let directory = tempfile::Builder::new()
                .prefix(&format!("{kind}-"))
                .tempdir_in(state)?
                .keep();
            let receipt = directory.join("export.json");
            let receipt = receipt.to_str().ok_or("Invalid receipt path")?;
            export(
                &a.get("--source", "."),
                &a.get("--host", "macbook"),
                Path::new(receipt),
                &[],
                true,
            )?;
            if ["build", "deploy"].contains(&kind.as_str()) {
                deploy(
                    receipt,
                    &a.get("--configuration", "macbook-pro-m4"),
                    &kind,
                    &a.command,
                )
            } else {
                let mut command = match kind.as_str() {
                    "check" => vec!["nix", "flake", "check", "--no-write-lock-file"],
                    "test" => vec![
                        "nix",
                        "develop",
                        "--no-write-lock-file",
                        "--command",
                        "nix-unit",
                        "--flake",
                        ".#libTests",
                    ],
                    _ => vec![],
                }
                .into_iter()
                .map(String::from)
                .collect::<Vec<_>>();
                command.extend(a.command);
                run(receipt, &command)
            }
        }
        "_verify" | "_run" => remote_dispatch(
            &a.mode,
            &a.need("--snapshot")?,
            &a.need("--expected")?,
            a.options
                .get("--command-json")
                .and_then(|v| v.last())
                .map(String::as_str),
        ),
        _ => fail("Unknown mode"),
    }
}
fn main() {
    let args = match parse() {
        Ok(a) => a,
        Err(e) => {
            eprintln!("mac-source: {e}");
            std::process::exit(2);
        }
    };
    match dispatch(args) {
        Ok(code) => std::process::exit(code),
        Err(e) => {
            eprintln!("mac-source: {e}");
            std::process::exit(1);
        }
    }
}
