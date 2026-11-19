//! Own a thread-scoped transient service, including cancellation during launch.
use sha2::{Digest, Sha256};
use std::{env, io::Read, os::unix::process::ExitStatusExt, process::Stdio, time::Duration};
use tokio::{
    process::Command,
    signal::unix::{SignalKind, signal},
};
type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
async fn control(args: &[&str]) -> Result<std::process::Output> {
    Ok(nix_conf_process::run(
        Command::new("systemctl").arg("--user").args(args),
        None,
        Duration::from_secs(20),
    )
    .await?)
}
fn forward(name: &str) -> bool {
    let mut chars = name.chars();
    if !chars
        .next()
        .is_some_and(|c| c.is_ascii_alphabetic() || c == '_')
        || !chars.all(|c| c.is_ascii_alphanumeric() || c == '_')
    {
        return false;
    }
    !matches!(
        name,
        "INVOCATION_ID"
            | "JOURNAL_STREAM"
            | "SYSTEMD_EXEC_PID"
            | "NOTIFY_SOCKET"
            | "RUNTIME_DIRECTORY"
            | "STATE_DIRECTORY"
            | "CACHE_DIRECTORY"
            | "LOGS_DIRECTORY"
            | "CONFIGURATION_DIRECTORY"
            | "CREDENTIALS_DIRECTORY"
            | "ENCRYPTED_CREDENTIALS_DIRECTORY"
            | "CODEX_LAUNCH_UNIT"
    ) && !name.starts_with("WATCHDOG_")
        && !name.starts_with("LISTEN_")
}
fn uuid() -> Result<String> {
    let mut bytes = [0u8; 16];
    std::fs::File::open("/dev/urandom")?.read_exact(&mut bytes)?;
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    let hex: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
    Ok(format!(
        "{}-{}-{}-{}-{}",
        &hex[..8],
        &hex[8..12],
        &hex[12..16],
        &hex[16..20],
        &hex[20..]
    ))
}
async fn main_result() -> Result<i32> {
    let thread = env::var("CODEX_THREAD_ID")
        .ok()
        .filter(|s| !s.is_empty())
        .ok_or("codex-task requires the owning CODEX_THREAD_ID")?;
    let prefix = format!(
        "codex-task-{}",
        &format!("{:x}", Sha256::digest(thread.as_bytes()))[..32]
    );
    let args: Vec<_> = env::args_os().skip(1).collect();
    let action = args.first().and_then(|s| s.to_str()).unwrap_or("");
    match action {
        "run" if args.len() > 1 => {
            // Subscribe before spawning: signals cannot bypass service cleanup.
            let mut term = signal(SignalKind::terminate())?;
            let mut int = signal(SignalKind::interrupt())?;
            let mut hup = signal(SignalKind::hangup())?;
            let unit = format!("{prefix}-{}.service", uuid()?);
            let mask = rustix::process::umask(rustix::fs::Mode::empty());
            rustix::process::umask(mask);
            let mut working_directory = std::ffi::OsString::from("--working-directory=");
            working_directory.push(env::current_dir()?.as_os_str());
            let mut command = Command::new("systemd-run");
            command
                .args([
                    "--user",
                    "--wait",
                    "--pipe",
                    "--collect",
                    "--quiet",
                    "--service-type=exec",
                    "--expand-environment=no",
                    "--slice=app-codex.slice",
                ])
                .arg(format!("--unit={unit}"))
                .arg(working_directory)
                .args([
                    "--property=KillMode=control-group",
                    "--property=TimeoutStopSec=15s",
                    "--property=CPUWeight=50",
                    "--property=IOWeight=50",
                ])
                .arg(format!("--property=UMask={:04o}", mask.bits()));
            for (name, _) in env::vars_os() {
                if name.to_str().is_some_and(forward) {
                    let mut arg = std::ffi::OsString::from("--setenv=");
                    arg.push(name);
                    command.arg(arg);
                }
            }
            command
                .arg("--")
                .args(&args[1..])
                .stdin(Stdio::inherit())
                .stdout(Stdio::inherit())
                .stderr(Stdio::inherit())
                .kill_on_drop(true);
            let mut child = command.spawn()?;
            let outcome = tokio::select! {
                status = child.wait() => status.map(|s| (s.code().unwrap_or_else(||128+s.signal().unwrap_or(1)), None)),
                _ = term.recv() => Ok((143, Some(rustix::process::Signal::TERM))),
                _ = int.recv() => Ok((130, Some(rustix::process::Signal::INT))),
                _ = hup.recv() => Ok((129, Some(rustix::process::Signal::HUP))),
            };
            let _stop_result = control(&["stop", "--", &unit]).await;
            if let Ok((_, Some(sig))) = outcome {
                // child.wait has not reaped the client on this branch.
                if let Some(pid) = child
                    .id()
                    .and_then(|p| rustix::process::Pid::from_raw(p as i32))
                {
                    let _signal_result = rustix::process::kill_process(pid, sig);
                }
                if tokio::time::timeout(Duration::from_secs(2), child.wait())
                    .await
                    .is_err()
                {
                    let _kill_result = child.kill().await;
                }
            } else if outcome.is_err() {
                let _kill_result = child.kill().await;
            }
            let _stop_result = control(&["stop", "--", &unit]).await;
            Ok(outcome?.0)
        }
        "list" | "finish" => {
            let pattern = format!("{prefix}-*.service");
            let output = control(&[
                "list-units",
                "--type=service",
                "--all",
                "--plain",
                "--no-legend",
                &pattern,
            ])
            .await?;
            if !output.status.success() {
                return Err("Unit listing failed".into());
            }
            let listing = String::from_utf8(output.stdout)?;
            // Validate manager output again before allowing any stop operation.
            let units: Vec<_> = listing
                .lines()
                .filter_map(|s| s.split_whitespace().next())
                .filter(|s| {
                    s.starts_with(&format!("{prefix}-"))
                        && s.ends_with(".service")
                        && !s.contains('/')
                })
                .collect();
            if action == "list" {
                for unit in units {
                    println!("{unit}");
                }
            } else if !units.is_empty() {
                let mut args = vec!["stop", "--"];
                args.extend(units);
                if !control(&args).await?.status.success() {
                    return Err("Task stop failed".into());
                }
            }
            Ok(0)
        }
        _ => Err("Usage: codex-task {run COMMAND [ARGS...]|list|finish}".into()),
    }
}
#[tokio::main(flavor = "current_thread")]
async fn main() {
    match main_result().await {
        Ok(code) => std::process::exit(code),
        Err(e) => {
            eprintln!("{e}");
            std::process::exit(2)
        }
    }
}
