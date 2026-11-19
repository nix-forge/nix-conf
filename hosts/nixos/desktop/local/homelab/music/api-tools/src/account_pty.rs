//! Private PTY exchange: never forward child output or password-bearing diagnostics.
use rustix::{
    process::{Pid, Signal, kill_process_group},
    pty, termios,
};
use std::{
    error::Error, fs::OpenOptions, os::unix::ffi::OsStrExt, path::Path, process::Stdio,
    time::Duration,
};
use tokio::io::unix::AsyncFd;
type Result<T> = std::result::Result<T, Box<dyn Error>>;
struct Group(Pid);
impl Drop for Group {
    fn drop(&mut self) {
        let _signal_result = kill_process_group(self.0, Signal::KILL);
    }
}
pub async fn create(
    config: &std::ffi::OsStr,
    username: &str,
    password: &str,
    role: &str,
) -> Result<u8> {
    use tokio::signal::unix::{SignalKind, signal};
    let mut term = signal(SignalKind::terminate())?;
    let mut interrupt = signal(SignalKind::interrupt())?;
    let mut hangup = signal(SignalKind::hangup())?;
    let mut quit = signal(SignalKind::quit())?;
    if username.is_empty()
        || password.is_empty()
        || password.contains(['\r', '\n', '\0'])
        || !["admin", "regular"].contains(&role)
    {
        return Err("invalid account input".into());
    }
    let master =
        pty::openpt(pty::OpenptFlags::RDWR | pty::OpenptFlags::NOCTTY | pty::OpenptFlags::CLOEXEC)?;
    rustix::fs::fcntl_setfl(&master, rustix::fs::OFlags::NONBLOCK)?;
    pty::grantpt(&master)?;
    pty::unlockpt(&master)?;
    let name = pty::ptsname(&master, Vec::new())?;
    let slave = OpenOptions::new()
        .read(true)
        .write(true)
        .open(Path::new(std::ffi::OsStr::from_bytes(name.to_bytes())))?;
    let mut attrs = termios::tcgetattr(&slave)?;
    attrs
        .local_modes
        .remove(termios::LocalModes::ECHO | termios::LocalModes::ECHONL);
    termios::tcsetattr(&slave, termios::OptionalActions::Now, &attrs)?;
    let mut command = tokio::process::Command::new("navidrome");
    command
        .args([std::ffi::OsStr::new("--configfile"), config])
        .args(["user", "create", "--username", username]);
    if role == "admin" {
        command.arg("--admin");
    }
    command
        .env_remove("MUSIC_DISCOVERY_PASSWORD")
        .env_remove("MUSIC_DISCOVERY_USERNAME")
        .env_remove("MUSIC_DISCOVERY_ROLE");
    command
        .stdin(Stdio::from(slave.try_clone()?))
        .stdout(Stdio::from(slave.try_clone()?))
        .stderr(Stdio::from(slave))
        .process_group(0)
        .kill_on_drop(true);
    let mut child = command.spawn()?;
    drop(command); // release the parent copies of the slave so EOF is observable

    let pid =
        Pid::from_raw(i32::try_from(child.id().ok_or("missing child")?)?).ok_or("invalid child")?;
    let group = Group(pid);
    // Owned descriptors remain stable for the lifetime of each registration.
    #[allow(
        deprecated,
        reason = "safe owned-descriptor API retained until its replacement is available"
    )]
    let terminal = AsyncFd::new(master)?;
    let exchange = async {
        let mut stage = 0;
        let mut pending = Vec::new();
        loop {
            let mut ready = terminal.readable().await?;
            let mut buffer = [0u8; 4096];
            let count = match ready.try_io(|fd| {
                rustix::io::read(fd.get_ref(), &mut buffer).map_err(std::io::Error::from)
            }) {
                Err(_) => continue,
                Ok(Err(e)) if e.raw_os_error() == Some(5) => break,
                Ok(result) => result?,
            };
            if count == 0 {
                break;
            }
            pending.extend_from_slice(&buffer[..count]);
            let prompt: &[u8] = match stage {
                0 => b"Enter new password",
                1 => b"Confirm new password",
                _ => b"",
            };
            if stage < 2 && pending.windows(prompt.len()).any(|w| w == prompt) {
                // Discard all prior output, including anything that could echo a secret.
                pending.clear();
                let input = format!("{password}\r");
                let mut bytes = input.as_bytes();
                while !bytes.is_empty() {
                    let mut ready = terminal.writable().await?;
                    if let Ok(result) = ready.try_io(|fd| {
                        rustix::io::write(fd.get_ref(), bytes).map_err(std::io::Error::from)
                    }) {
                        let n = result?;
                        if n == 0 {
                            return Err::<(), Box<dyn Error>>("PTY closed".into());
                        }
                        bytes = &bytes[n..];
                    }
                }
                stage += 1;
            }
            if pending.len() > 4096 {
                pending.drain(..pending.len() - 4096);
            }
        }
        if stage != 2 {
            return Err("password prompt exchange incomplete".into());
        }
        Ok(())
    };
    // Includes fragmented prompts, writes, EOF, and child exit under one deadline.
    let operation = tokio::time::timeout(Duration::from_secs(30), async {
        exchange.await?;
        #[allow(
            deprecated,
            reason = "safe owned-descriptor API retained until its replacement is available"
        )]
        let exited = AsyncFd::new(rustix::process::pidfd_open(
            pid,
            rustix::process::PidfdFlags::empty(),
        )?)?;
        let _ready = exited.readable().await?;
        Ok::<(), Box<dyn Error>>(())
    });
    let mut cancelled = None;
    let result = tokio::select! {
        result = operation => Some(result),
        _ = term.recv() => { cancelled = Some(143); None },
        _ = interrupt.recv() => { cancelled = Some(130); None },
        _ = hangup.recv() => { cancelled = Some(129); None },
        _ = quit.recv() => { cancelled = Some(131); None },
    };
    drop(group); // leader still reserved: clean descendants before reaping
    let status = child.wait().await?;
    if let Some(code) = cancelled {
        return Ok(code);
    }
    let result = result.ok_or("missing PTY outcome")?;
    result??;
    Ok(u8::try_from(status.code().unwrap_or(1)).unwrap_or(1))
}
