//! Reconcile selected whole disks without overwriting measured operator policy.
use serde_json::Value;
use std::{env, fs, path::Path, process::ExitCode, time::Duration};
type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
fn enable(root: &Path, device: &str) -> Result<()> {
    let valid = device.split_once(':').is_some_and(|(a, b)| {
        !a.is_empty() && !b.is_empty() && a.bytes().chain(b.bytes()).all(|c| c.is_ascii_digit())
    });
    if !valid {
        return Err("expected a whole-disk major:minor device number".into());
    }
    for name in ["io.cost.model", "io.cost.qos"] {
        let text = fs::read_to_string(root.join(name))?;
        if text.lines().any(|line| {
            let mut words = line.split_whitespace();
            words.next() == Some(device) && words.any(|word| word == "ctrl=user")
        }) {
            return Ok(());
        }
    }
    let _writable = ["io.cost.model", "io.cost.qos"]
        .map(|name| fs::OpenOptions::new().write(true).open(root.join(name)))
        .into_iter()
        .collect::<std::io::Result<Vec<_>>>()?;
    // Opening existing controller files rather than creating paths retains the
    // kernel-availability veto, including during boot and concurrent removal.
    use std::io::Write;
    for (name, settings) in [
        ("io.cost.model", "ctrl=auto"),
        ("io.cost.qos", "enable=1 ctrl=auto"),
    ] {
        let mut file = fs::OpenOptions::new()
            .write(true)
            .truncate(true)
            .open(root.join(name))?;
        let command = format!("{device} {settings}\n");
        // Each cgroup write is one complete command; formatting directly into
        // File can emit several writes that the kernel parses separately.
        if file.write(command.as_bytes())? != command.len() {
            return Err("partial controller command write".into());
        }
    }
    Ok(())
}
async fn run() -> Result<()> {
    let args: Vec<_> = env::args().skip(1).collect();
    match args.as_slice() {
        [mode, root, device] if mode == "enable" => enable(Path::new(root), device),
        [mode, policy] if mode == "reconcile" => {
            let policy: Value = serde_json::from_slice(&fs::read(policy)?)?;
            let patterns = policy["patterns"]
                .as_array()
                .ok_or("patterns required")?
                .iter()
                .map(|v| -> Result<_> {
                    Ok(glob::Pattern::new(
                        v.as_str().ok_or("pattern must be a string")?,
                    )?)
                })
                .collect::<Result<Vec<_>>>()?;
            let root = Path::new(
                policy["cgroupRoot"]
                    .as_str()
                    .ok_or("controller root required")?,
            );
            for entry in fs::read_dir(
                policy["deviceRoot"]
                    .as_str()
                    .ok_or("device root required")?,
            )? {
                let entry = entry?;
                if !entry
                    .file_name()
                    .to_str()
                    .is_some_and(|name| patterns.iter().any(|p| p.matches(name)))
                {
                    continue;
                }
                let Ok(device) = fs::read_to_string(entry.path().join("dev")) else {
                    continue;
                };
                let mut command = tokio::process::Command::new(
                    policy["udevadm"].as_str().ok_or("udevadm required")?,
                );
                command
                    .args(["info", "--query=property"])
                    .arg(format!("--path={}", entry.path().display()));
                let Ok(output) =
                    nix_conf_process::run(&mut command, None, Duration::from_secs(10)).await
                else {
                    continue;
                };
                if !output.status.success() {
                    continue;
                }
                let properties = String::from_utf8(output.stdout)?;
                if properties.lines().any(|line| {
                    line.strip_prefix("IOCOST_SOLUTIONS=")
                        .is_some_and(|v| !v.is_empty())
                }) {
                    continue;
                }
                // Re-read after udev: disappearing devices are normal here.
                let Ok(current) = fs::read_to_string(entry.path().join("dev")) else {
                    continue;
                };
                if current != device {
                    continue;
                }
                enable(root, current.trim_end_matches('\n'))?;
            }
            Ok(())
        }
        _ => Err("usage: adaptive-iocost enable CGROUP_ROOT MAJOR:MINOR | reconcile POLICY".into()),
    }
}
async fn guarded() -> Result<u8> {
    let args: Vec<_> = env::args().skip(1).collect();
    if args.first().is_some_and(|s| s == "enable")
        && (args.len() != 3
            || !args[2].split_once(':').is_some_and(|(a, b)| {
                !a.is_empty()
                    && !b.is_empty()
                    && a.bytes().chain(b.bytes()).all(|c| c.is_ascii_digit())
            }))
    {
        eprintln!("expected a whole-disk major:minor device number");
        return Ok(2);
    }
    use tokio::signal::unix::{SignalKind, signal};
    let mut term = signal(SignalKind::terminate())?;
    let mut interrupt = signal(SignalKind::interrupt())?;
    let mut hup = signal(SignalKind::hangup())?;
    tokio::select! {result=run()=>result.map(|()|0),_=term.recv()=>Ok(143),_=interrupt.recv()=>Ok(130),_=hup.recv()=>Ok(129)}
}
#[tokio::main(flavor = "current_thread")]
async fn main() -> ExitCode {
    match guarded().await {
        Ok(code) => ExitCode::from(code),
        Err(e) => {
            eprintln!("adaptive-iocost: {e}");
            ExitCode::FAILURE
        }
    }
}
