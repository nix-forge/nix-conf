//! Display-scoped locker lifetime and explicit authenticated lock recovery.
use fs2::FileExt;
use sha2::{Digest, Sha256};
use std::{
    env,
    fs::{File, OpenOptions},
    os::unix::{
        fs::{MetadataExt, OpenOptionsExt},
        process::ExitStatusExt,
    },
    path::PathBuf,
    process::Stdio,
    time::Duration,
};
use tokio::{
    process::{Child, Command},
    signal::unix::{Signal, SignalKind, signal},
};
type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
struct Signals {
    term: Signal,
    int: Signal,
    hup: Signal,
}
impl Signals {
    fn new() -> Result<Self> {
        Ok(Self {
            term: signal(SignalKind::terminate())?,
            int: signal(SignalKind::interrupt())?,
            hup: signal(SignalKind::hangup())?,
        })
    }
    async fn receive(&mut self) -> i32 {
        tokio::select! { _=self.term.recv()=>143, _=self.int.recv()=>130, _=self.hup.recv()=>129 }
    }
}
fn code(status: std::process::ExitStatus) -> i32 {
    status
        .code()
        .unwrap_or_else(|| 128 + status.signal().unwrap_or(1))
}
fn lock_file(domain: &str, key: &str) -> Result<File> {
    let runtime = PathBuf::from(env::var("XDG_RUNTIME_DIR")?);
    let metadata = std::fs::metadata(&runtime)?;
    let uid = rustix::process::getuid().as_raw();
    if metadata.uid() != uid || metadata.mode() & 0o077 != 0 {
        return Err("Runtime directory must be private and owned by this user".into());
    }
    let hash = format!("{:x}", Sha256::digest(key.as_bytes()));
    let file = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .custom_flags(rustix::fs::OFlags::NOFOLLOW.bits() as i32)
        .open(runtime.join(format!("desktop-session-{domain}-{hash}.lock")))?;
    let metadata = file.metadata()?;
    if !metadata.is_file()
        || metadata.uid() != uid
        || metadata.mode() & 0o077 != 0
        || metadata.nlink() != 1
    {
        return Err("Unsafe lock file".into());
    }
    Ok(file)
}
async fn end_child(child: &mut Child, status: i32) {
    // Only called while the child is still owned and has not been reaped.
    let sig = match status {
        129 => rustix::process::Signal::HUP,
        130 => rustix::process::Signal::INT,
        _ => rustix::process::Signal::TERM,
    };
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
}
async fn client(args: &[String], signals: &mut Signals) -> Result<i32> {
    let display = env::var("WAYLAND_DISPLAY")?;
    if display.is_empty() {
        return Err("A Wayland display is required".into());
    }
    let mode = args.first().map(String::as_str).unwrap_or("");
    let file = lock_file("lock", &display)?;
    match file.try_lock_exclusive() {
        Ok(()) => (),
        Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
            return match mode {
                "lock" | "running" => Ok(0),
                _ => Err("Expected lock or running".into()),
            };
        }
        Err(e) => return Err(e.into()),
    }
    if mode == "running" {
        return Ok(1);
    }
    if mode != "lock" || args.len() < 2 {
        return Err("Expected lock COMMAND or running".into());
    }
    // Keep the CLOEXEC lock in the parent for the entire real hyprlock lifetime.
    let mut child = Command::new(&args[1])
        .args(&args[2..])
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .kill_on_drop(true)
        .spawn()?;
    let result = tokio::select! { status=child.wait()=>Ok(code(status?)), status=signals.receive()=>{end_child(&mut child,status).await;Ok(status)} };
    drop(file);
    result
}
struct Controller<'a> {
    systemctl: &'a str,
    escape: &'a str,
    hyprctl: &'a str,
    timeout: Duration,
}
impl Controller<'_> {
    async fn call(&self, program: &str, args: &[&str]) -> Result<std::process::Output> {
        Ok(nix_conf_process::run(Command::new(program).args(args), None, self.timeout).await?)
    }
    async fn checked(&self, program: &str, args: &[&str]) -> Result<Vec<u8>> {
        let output = self.call(program, args).await?;
        if !output.status.success() {
            return Err(format!("IPC failed: {}", String::from_utf8_lossy(&output.stderr)).into());
        }
        Ok(output.stdout)
    }
    async fn policy(&self, instance: &str) -> Result<bool> {
        let bytes = self
            .checked(
                self.hyprctl,
                &[
                    "-i",
                    instance,
                    "-j",
                    "getoption",
                    "misc:allow_session_lock_restore",
                ],
            )
            .await?;
        serde_json::from_slice::<serde_json::Value>(&bytes)?["bool"]
            .as_bool()
            .ok_or_else(|| "Expected boolean restoration policy".into())
    }
    async fn set_policy(&self, instance: &str, value: bool) -> Result<()> {
        self.checked(
            self.hyprctl,
            &[
                "-i",
                instance,
                "eval",
                &format!("hl.config({{misc={{allow_session_lock_restore={value}}}}})"),
            ],
        )
        .await?;
        if self.policy(instance).await? != value {
            return Err("Compositor did not apply session-lock policy".into());
        }
        Ok(())
    }
}
async fn controller(args: &[String], signals: &mut Signals) -> Result<i32> {
    if args.len() != 5 {
        return Err("Expected controller configuration and mode".into());
    }
    let ctl = Controller {
        systemctl: &args[0],
        escape: &args[1],
        hyprctl: &args[2],
        timeout: Duration::from_secs(args[3].parse()?),
    };
    let mode = args[4].as_str();
    if mode == "running" {
        return client(&["running".into()], signals).await;
    }
    if !["lock", "recover"].contains(&mode) {
        return Err("Expected lock, recover, or running".into());
    }
    let display = env::var("WAYLAND_DISPLAY")?;
    if display.is_empty() {
        return Err("A Wayland display is required".into());
    }
    let unit = ctl
        .checked(
            ctl.escape,
            &["--template=desktop-session-lock@.service", &display],
        )
        .await?;
    let unit = String::from_utf8(unit)?.trim().to_owned();
    if unit.is_empty() {
        return Err("Empty escaped unit".into());
    }
    if mode == "lock" {
        return Ok(code(
            ctl.call(ctl.systemctl, &["--user", "start", &unit])
                .await?
                .status,
        ));
    }
    let bytes = ctl.checked(ctl.hyprctl, &["-j", "instances"]).await?;
    let instances: serde_json::Value = serde_json::from_slice(&bytes)?;
    let matching: Vec<_> = instances
        .as_array()
        .ok_or("Expected compositor list")?
        .iter()
        .filter(|v| v["wl_socket"].as_str() == Some(&display))
        .collect();
    if matching.len() != 1 {
        return Err("Expected one compositor for this display".into());
    }
    let instance = matching[0]["instance"]
        .as_str()
        .filter(|s| !s.is_empty())
        .ok_or("Missing compositor instance")?;
    let file = lock_file("recovery", instance)?;
    // Blocking flock is an event wait. The worker owns the fd until acquisition;
    // cancellation before acquisition cannot change compositor policy.
    let file = tokio::select! {
        result=tokio::task::spawn_blocking(move || {file.lock_exclusive()?;Ok::<_,std::io::Error>(file)})=>result??,
        status=signals.receive()=>return Ok(status),
    };
    let previous = tokio::select! { result=ctl.policy(instance)=>result?, status=signals.receive()=>return Ok(status) };
    let mut manager: Option<Child> = None;
    let operation = async {
        if ctl
            .call(ctl.systemctl, &["--user", "is-failed", "--quiet", &unit])
            .await?
            .status
            .success()
        {
            ctl.checked(ctl.systemctl, &["--user", "reset-failed", &unit])
                .await?;
        }
        ctl.set_policy(instance, true).await?;
        manager = Some(
            Command::new(ctl.systemctl)
                .args(["--user", "start", "--wait", &unit])
                .kill_on_drop(true)
                .spawn()?,
        );
        let status = manager.as_mut().ok_or("Missing manager")?.wait().await?;
        manager = None; // No PID survives successful reap.
        Ok::<_, Box<dyn std::error::Error>>(code(status))
    };
    let result = tokio::select! {result=operation=>result,status=signals.receive()=>Ok(status)};
    // Signal handlers remain installed, but cleanup cannot be cancelled by another
    // signal. One overall bound covers restoration, verification and manager exit.
    let cleanup = tokio::time::timeout(ctl.timeout * 2 + Duration::from_secs(3), async {
        let restored = ctl.set_policy(instance, previous).await;
        if let Some(mut child) = manager.take() {
            end_child(&mut child, 143).await;
        }
        restored
    })
    .await;
    drop(file);
    cleanup??;
    result
}
#[tokio::main(flavor = "current_thread")]
async fn main() {
    let args: Vec<_> = env::args().skip(1).collect();
    let result = async {
        let mut signals = Signals::new()?;
        if args.first().is_some_and(|s| s == "client") {
            client(&args[1..], &mut signals).await
        } else {
            controller(&args, &mut signals).await
        }
    }
    .await;
    match result {
        Ok(status) => std::process::exit(status),
        Err(e) => {
            eprintln!("{e}");
            std::process::exit(2)
        }
    }
}
