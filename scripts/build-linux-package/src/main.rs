//! Archive and root an immutable source before building, retaining final receipts.
use nix::{
    sys::signal::{Signal, killpg},
    unistd::Pid,
};
use serde_json::{Value, json};
use signal_hook::{
    consts::signal::{SIGHUP, SIGINT, SIGTERM},
    iterator::Signals,
};
use std::{
    collections::BTreeSet,
    error::Error,
    fs::{self, File},
    io::Write,
    os::unix::process::{CommandExt, ExitStatusExt},
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::{Arc, Mutex},
    time::{Instant, SystemTime, UNIX_EPOCH},
};

type Result<T> = std::result::Result<T, Box<dyn Error>>;
fn now() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0., |v| v.as_secs_f64())
}
fn rounded(value: f64) -> f64 {
    (value * 100.).round() / 100.
}
fn save(path: &Path, value: &Value) -> Result<()> {
    let mut file =
        tempfile::NamedTempFile::new_in(path.parent().ok_or("Missing receipt directory")?)?;
    serde_json::to_writer_pretty(&mut file, value)?;
    writeln!(file)?;
    file.persist(path)?;
    Ok(())
}
fn archives(value: &Value, result: &mut BTreeSet<String>) -> Result<()> {
    let value = value.as_object().ok_or("Invalid archive record")?;
    if let Some(path) = value.get("path") {
        let path = path.as_str().ok_or("Invalid archived path")?;
        if Path::new(path).parent() != Some(Path::new("/nix/store")) {
            return Err("Flake archive returned a non-store source".into());
        }
        result.insert(path.to_string());
    }
    if let Some(inputs) = value.get("inputs") {
        for dependency in inputs.as_object().ok_or("Invalid archive inputs")?.values() {
            archives(dependency, result)?;
        }
    }
    Ok(())
}
#[derive(Default)]
struct ProcessState {
    signal: i32,
    pid: Option<Pid>,
}
struct Runner(Arc<Mutex<ProcessState>>);
impl Runner {
    fn cancelled(&self) -> Result<i32> {
        Ok(self
            .0
            .lock()
            .map_err(|_| "Cancellation state unavailable")?
            .signal)
    }
    fn run(&self, args: &[String], output: Option<&Path>) -> Result<i32> {
        let mut state = self
            .0
            .lock()
            .map_err(|_| "Cancellation state unavailable")?;
        if state.signal != 0 {
            return Ok(128 + state.signal);
        }
        let mut command = Command::new(args.first().ok_or("Empty command")?);
        command.args(&args[1..]).process_group(0);
        if let Some(path) = output {
            command.stdout(Stdio::from(File::create(path)?));
        } else {
            command.stdout(Stdio::null());
        }
        let mut child = command.spawn()?;
        state.pid = Some(Pid::from_raw(child.id().try_into()?));
        drop(state);
        // Observe exit without reaping first: while the cancellation observer
        // holds this PID, the kernel must not recycle it for an unrelated job.
        #[cfg(target_os = "linux")]
        loop {
            use nix::sys::wait::{Id, WaitPidFlag, waitid};
            match waitid(
                Id::Pid(Pid::from_raw(child.id().try_into()?)),
                WaitPidFlag::WEXITED | WaitPidFlag::WNOWAIT,
            ) {
                Ok(_) => break,
                Err(nix::errno::Errno::EINTR) => continue,
                Err(error) => return Err(error.into()),
            }
        }
        let mut state = self
            .0
            .lock()
            .map_err(|_| "Cancellation state unavailable")?;
        state.pid = None;
        let status = child.wait()?;
        if state.signal != 0 {
            return Ok(128 + state.signal);
        }
        Ok(status
            .code()
            .unwrap_or_else(|| 128 + status.signal().unwrap_or(1)))
    }
}
fn command(args: &[&str]) -> Vec<String> {
    args.iter().map(|s| s.to_string()).collect()
}
fn execute(args: &[String], state: &Path, report: &mut Value, runner: &Runner) -> Result<i32> {
    let [
        repository,
        build_system,
        host_system,
        package,
        _,
        expression,
    ] = args
    else {
        return Err("Require six arguments".into());
    };
    let archive_file = state.join("archive.json");
    let status = runner.run(
        &command(&[
            "nix",
            "flake",
            "archive",
            "--json",
            "--no-update-lock-file",
            repository,
        ]),
        Some(&archive_file),
    )?;
    if status != 0 {
        return Ok(status);
    }
    let archived: Value = serde_json::from_slice(&fs::read(&archive_file)?)?;
    let snapshot = archived
        .get("path")
        .and_then(Value::as_str)
        .ok_or("Missing archive source")?;
    let mut sources = BTreeSet::new();
    archives(&archived, &mut sources)?;
    report["source_snapshot"] = json!(snapshot);
    report["phase"] = json!("source_roots");
    save(&state.join("status.json"), report)?;
    for (index, source) in sources.iter().enumerate() {
        let status = runner.run(
            &command(&[
                "nix-store",
                "--add-root",
                state
                    .join(format!("source-{index}"))
                    .to_str()
                    .ok_or("Invalid state path")?,
                "--indirect",
                "-r",
                source,
            ]),
            None,
        )?;
        if status != 0 {
            return Ok(status);
        }
    }
    report["phase"] = json!("build");
    let build = command(&[
        "nix",
        "build",
        "--json",
        "--print-build-logs",
        "--max-jobs",
        "1",
        "--cores",
        &report["compiler_jobs"].to_string(),
        "--builders",
        "",
        "--option",
        "extra-platforms",
        if build_system == "x86_64-linux" {
            "i686-linux"
        } else {
            ""
        },
        "--out-link",
        state.join("result").to_str().ok_or("Invalid state path")?,
        "--impure",
        "--file",
        expression,
        "--argstr",
        "repository",
        snapshot,
        "--argstr",
        "buildSystem",
        build_system,
        "--argstr",
        "hostSystem",
        host_system,
        "--argstr",
        "package",
        package,
    ]);
    report["command"] = json!(build);
    save(&state.join("status.json"), report)?;
    let outputs_file = state.join("outputs.json");
    let status = runner.run(&build, Some(&outputs_file))?;
    if status == 0 {
        let outputs: Value = serde_json::from_slice(&fs::read(outputs_file)?)?;
        for result in outputs.as_array().ok_or("Invalid build results")? {
            for output in result["outputs"]
                .as_object()
                .ok_or("Invalid build outputs")?
                .values()
            {
                println!("{}", output.as_str().ok_or("Invalid output path")?);
            }
        }
    }
    Ok(status)
}
fn main_result() -> Result<i32> {
    let args: Vec<_> = std::env::args().skip(1).collect();
    let [repository, build_system, host_system, package, directory, _] = args.as_slice() else {
        return Err(
            "Require repository build_system host_system package directory expression".into(),
        );
    };
    let platforms = ["x86_64-linux", "aarch64-linux"];
    if !platforms.contains(&build_system.as_str()) || !platforms.contains(&host_system.as_str()) {
        return Err("Unsupported Linux build/host platform pair".into());
    }
    let state = PathBuf::from(directory);
    let started = now();
    let monotonic = Instant::now();
    let output = Command::new("nix")
        .args(["config", "show", "cores"])
        .stderr(Stdio::inherit())
        .output()?;
    if !output.status.success() {
        return Err("Cannot read configured compiler budget".into());
    }
    let configured: usize = String::from_utf8(output.stdout)?.trim().parse()?;
    let cpus = std::thread::available_parallelism()?.get();
    let jobs = if configured > 0 {
        configured.min(cpus)
    } else {
        (cpus * 3 / 4).clamp(1, 8)
    };
    let queued = fs::metadata(&state)?
        .modified()?
        .duration_since(UNIX_EPOCH)?
        .as_secs_f64();
    let mut report = json!({"repository": repository, "build_system": build_system, "host_system": host_system, "package": package, "compiler_jobs": jobs, "max_jobs": 1, "mode": if build_system == host_system { "native" } else { "cross" }, "started_at": started, "queue_seconds": rounded((started-queued).max(0.)), "queue_measurement": "Approximate wait since launcher roots were prepared; filesystem timestamps use wall time.", "phase": "archive", "status": "running"});
    let mut signals = Signals::new([SIGHUP, SIGINT, SIGTERM])?;
    let handle = signals.handle();
    let runner = Runner(Arc::new(Mutex::new(ProcessState::default())));
    let signal_state = Arc::clone(&runner.0);
    let observer = std::thread::spawn(move || {
        for signal in signals.forever() {
            if let Ok(mut state) = signal_state.lock() {
                if state.signal == 0 {
                    state.signal = signal;
                }
                if let (Some(pid), Ok(signal)) = (state.pid, Signal::try_from(signal)) {
                    let _signal_result = killpg(pid, signal);
                }
            }
        }
    });
    let result = save(&state.join("status.json"), &report)
        .and_then(|()| execute(&args, &state, &mut report, &runner));
    let cancelled = runner.cancelled()?;
    let status = if cancelled != 0 {
        128 + cancelled
    } else {
        result.as_ref().copied().unwrap_or(1)
    };
    if result.is_err() {
        report["error"] =
            json!("Build operation failed; inspect the phase and command diagnostics");
    }
    report["exit_status"] = json!(status);
    report["finished_at"] = json!(now());
    report["execution_seconds"] = json!(rounded(monotonic.elapsed().as_secs_f64()));
    report["status"] = json!(if status == 0 {
        "passed"
    } else if [129, 130, 143].contains(&status) {
        "cancelled"
    } else {
        "failed"
    });
    let saved = save(&state.join("status.json"), &report);
    handle.close();
    observer.join().map_err(|_| "Signal observer failed")?;
    saved?;
    if let Err(error) = result {
        eprintln!("build-linux-package: {error}");
    }
    Ok(status)
}
fn main() {
    match main_result() {
        Ok(status) => std::process::exit(status),
        Err(error) => {
            eprintln!("build-linux-package: {error}");
            std::process::exit(1);
        }
    }
}
