//! Serialize application exports and disposable drills, always restarting writers.
use rustix::{
    event::{PollFd, PollFlags, Timespec, poll},
    process::{Pid, PidfdFlags, Signal, kill_process_group, pidfd_open},
};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    env,
    fs::{self, File, OpenOptions},
    io::{Read, Write},
    os::unix::{
        fs::{DirBuilderExt, PermissionsExt},
        net::UnixStream,
    },
    path::Path,
    process::{Command, Stdio},
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};
type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
struct Cancellation {
    flag: Arc<AtomicBool>,
    reader: UnixStream,
}
fn command(
    args: &[String],
    export: &Path,
    target: &Path,
    timeout: u64,
    cancel: Option<&Cancellation>,
    capture: bool,
) -> Result<Vec<u8>> {
    let start = Instant::now();
    // setsid execs the hook without forking because this child is not yet a
    // process-group leader. The child PID therefore owns the entire hook group.
    let mut child = Command::new("setsid")
        .args(args)
        .env("RECOVERY_EXPORT", export)
        .env("RECOVERY_TARGET", target)
        .stdout(if capture {
            Stdio::piped()
        } else {
            Stdio::inherit()
        })
        .spawn()?;
    let pid = Pid::from_raw(child.id() as i32).ok_or("invalid child PID")?;
    let output = child.stdout.take().map(|mut pipe| {
        std::thread::spawn(move || {
            let mut output = Vec::new();
            pipe.read_to_end(&mut output).map(|_| output)
        })
    });
    let result = (|| -> Result<()> {
        let fd = pidfd_open(pid, PidfdFlags::empty())?;
        loop {
            if cancel.is_some_and(|c| c.flag.load(Ordering::SeqCst)) {
                return Err("Recovery operation interrupted".into());
            }
            let remaining = Duration::from_secs(timeout)
                .checked_sub(start.elapsed())
                .ok_or("Recovery hook exceeded its deadline")?;
            let duration = Timespec::try_from(remaining)?;
            let mut fds = vec![PollFd::new(&fd, PollFlags::IN)];
            if let Some(cancel) = cancel {
                fds.push(PollFd::new(&cancel.reader, PollFlags::IN));
            }
            match poll(&mut fds, Some(&duration)) {
                Err(rustix::io::Errno::INTR) => continue,
                Err(error) => return Err(error.into()),
                Ok(0) => return Err("Recovery hook exceeded its deadline".into()),
                Ok(_) => {
                    if cancel.is_some_and(|c| c.flag.load(Ordering::SeqCst)) {
                        return Err("Recovery operation interrupted".into());
                    }
                    if fds[0].revents().contains(PollFlags::IN) {
                        break;
                    }
                }
            }
        }
        if !child.wait()?.success() {
            return Err("Recovery hook failed".into());
        }
        match rustix::process::test_kill_process_group(pid) {
            Err(rustix::io::Errno::SRCH) => Ok(()),
            Ok(()) => Err("Recovery hook left unfinished child processes".into()),
            Err(error) => Err(error.into()),
        }
    })();
    // Kill descendants before removing scratch or restarting stopped writers.
    let _signal_result = kill_process_group(pid, Signal::KILL);
    let _kill_result = child.kill();
    let _reap_result = child.wait();
    let bytes = if let Some(output) = output {
        output.join().map_err(|_| "output observer failed")??
    } else {
        Vec::new()
    };
    result?;
    Ok(bytes)
}
fn strings(policy: &Value, key: &str) -> Result<Vec<String>> {
    policy[key]
        .as_array()
        .ok_or("missing command")?
        .iter()
        .map(|v| {
            v.as_str()
                .map(str::to_owned)
                .ok_or_else(|| "invalid command argument".into())
        })
        .collect()
}
// Python's sorted JSON used spaces after separators. Preserve the receipt hash
// contract, including ensure_ascii encoding, so existing policy evidence agrees.
fn python_json(value: &Value) -> String {
    match value {
        Value::Array(items) => format!(
            "[{}]",
            items.iter().map(python_json).collect::<Vec<_>>().join(", ")
        ),
        Value::Object(items) => format!(
            "{{{}}}",
            items
                .iter()
                .map(|(k, v)| format!(
                    "{}: {}",
                    python_json(&Value::String(k.clone())),
                    python_json(v)
                ))
                .collect::<Vec<_>>()
                .join(", ")
        ),
        Value::String(s) => {
            let encoded = serde_json::to_string(s).unwrap_or_default();
            let mut result = String::new();
            for character in encoded.chars() {
                if character <= '\u{7e}' {
                    result.push(character);
                } else {
                    for unit in character.encode_utf16(&mut [0; 2]) {
                        result.push_str(&format!("\\u{unit:04x}"));
                    }
                }
            }
            result
        }
        _ => value.to_string(),
    }
}
fn receipt(directory: &Path, action: &str, success: bool, policy: &Value) -> Result<()> {
    let record = json!({"completed": SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs_f64(), "action": action, "result": if success { "success" } else { "failure" }, "policySha256": format!("{}", base16ct::HexDisplay(&Sha256::digest(python_json(policy)))), "scope": if action == "drill" { "isolated-application-drill" } else { "application-backup" }});
    for suffix in if success {
        vec!["attempt", "success"]
    } else {
        vec!["attempt"]
    } {
        let temporary = directory.join(format!("{action}-{suffix}.tmp"));
        fs::write(&temporary, format!("{record}\n"))?;
        fs::set_permissions(&temporary, fs::Permissions::from_mode(0o600))?;
        fs::rename(temporary, directory.join(format!("{action}-{suffix}.json")))?;
    }
    Ok(())
}
fn execute(policy: &Value, action: &str, cancel: &Cancellation) -> Result<()> {
    let directory = Path::new(
        policy["stateDirectory"]
            .as_str()
            .ok_or("missing state directory")?,
    );
    let timeout = policy["timeoutSeconds"]
        .as_u64()
        .filter(|n| *n > 0)
        .ok_or("invalid timeout")?;
    fs::DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(directory)?;
    let lock = OpenOptions::new()
        .create(true)
        .append(true)
        .open(directory.join("operation.lock"))?;
    rustix::fs::flock(&lock, rustix::fs::FlockOperation::NonBlockingLockExclusive)
        .map_err(|_| "An application recovery operation is already running")?;
    let result = (|| -> Result<()> {
        let scratch = tempfile::Builder::new()
            .prefix("operation-")
            .tempdir_in(directory)?;
        let export = scratch.path().join("export");
        let target = scratch.path().join("target");
        for path in [&export, &target] {
            fs::DirBuilder::new().mode(0o700).create(path)?;
        }
        let hook = |key: &str, cancellable| -> Result<()> {
            command(
                &strings(policy, key)?,
                &export,
                &target,
                timeout,
                if cancellable { Some(cancel) } else { None },
                false,
            )
            .map(|_| ())
        };
        if action == "drill" {
            for phase in ["recover", "restore", "check"] {
                hook(phase, true)?;
            }
            return Ok(());
        }
        let mut active = Vec::new();
        for unit in strings(policy, "units")? {
            let output = command(
                &[
                    "systemctl".into(),
                    "show".into(),
                    unit.clone(),
                    "--property=LoadState,ActiveState".into(),
                ],
                &export,
                &target,
                timeout,
                Some(cancel),
                true,
            )?;
            let output = String::from_utf8(output)?;
            let state: std::collections::HashMap<_, _> =
                output.lines().filter_map(|l| l.split_once('=')).collect();
            if state.get("LoadState") != Some(&"loaded")
                || !matches!(state.get("ActiveState"), Some(&"active" | &"inactive"))
            {
                return Err("Writer state is unavailable, failed or transitioning".into());
            }
            if state.get("ActiveState") == Some(&"active") {
                active.push(unit);
            }
        }
        let attempt = (|| -> Result<()> {
            for unit in &active {
                command(
                    &["systemctl".into(), "stop".into(), unit.clone()],
                    &export,
                    &target,
                    timeout,
                    Some(cancel),
                    false,
                )?;
            }
            hook("export", true)?;
            hook("backup", true)
        })();
        let mut failed = false;
        for unit in active.iter().rev() {
            if command(
                &["systemctl".into(), "start".into(), unit.clone()],
                &export,
                &target,
                timeout,
                None,
                false,
            )
            .is_err()
            {
                failed = true;
            }
        }
        if failed {
            return Err("One or more application writers could not restart".into());
        }
        attempt
    })();
    receipt(directory, action, result.is_ok(), policy)?;
    result
}
fn run() -> Result<()> {
    let args: Vec<_> = env::args_os().skip(1).collect();
    if args.len() != 2 || !["backup", "drill"].iter().any(|v| args[1] == *v) {
        return Err("expected policy and backup|drill".into());
    }
    let mut signals = signal_hook::iterator::Signals::new([
        signal_hook::consts::SIGINT,
        signal_hook::consts::SIGTERM,
    ])?;
    let handle = signals.handle();
    let flag = Arc::new(AtomicBool::new(false));
    let (reader, mut writer) = UnixStream::pair()?;
    let cancelled = Arc::clone(&flag);
    let observer = std::thread::spawn(move || {
        if signals.forever().next().is_some() {
            cancelled.store(true, Ordering::SeqCst);
            let _notification_result = writer.write_all(&[0]);
        }
    });
    let result = (|| {
        let policy = serde_json::from_reader(File::open(&args[0])?)?;
        execute(
            &policy,
            args[1].to_str().ok_or("invalid action")?,
            &Cancellation { flag, reader },
        )
    })();
    handle.close();
    let _observer_result = observer.join();
    result
}
fn main() {
    if run().is_err() {
        println!("Application recovery failed: RecoveryError");
        std::process::exit(1);
    }
}
