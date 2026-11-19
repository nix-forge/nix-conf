//! Capture bounded-lifetime children without polling; cancellation kills the group.
use rustix::process::{Pid, Signal, kill_process_group};
use std::{
    io,
    process::{Output, Stdio},
    sync::atomic::{AtomicBool, Ordering},
    time::Duration,
};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    process::Command,
};

struct Group {
    pid: Pid,
    armed: bool,
}
impl Group {
    fn signal(&self, signal: Signal) {
        let _signal_result = kill_process_group(self.pid, signal);
    }
}
impl Drop for Group {
    fn drop(&mut self) {
        if self.armed {
            self.signal(Signal::KILL);
        }
    }
}
// Observe without reaping. Keeping the leader reserved until group cleanup
// prevents a recycled PID/PGID from ever receiving this operation's signal.
#[cfg(target_os = "linux")]
async fn observe_exit(pid: Pid) -> io::Result<()> {
    let fd = rustix::process::pidfd_open(pid, rustix::process::PidfdFlags::empty())?;
    // OwnedFd cannot change identity while registered. Tokio's older safe
    // constructor remains valid for this owned descriptor (no raw mutable fd).
    #[allow(
        deprecated,
        reason = "safe owned-descriptor API retained until its replacement is available"
    )]
    let descriptor = tokio::io::unix::AsyncFd::new(fd)?;
    let _ready = descriptor.readable().await?;
    Ok(())
}
#[cfg(not(target_os = "linux"))]
async fn observe_exit(pid: Pid) -> io::Result<()> {
    // POSIX waitid(WNOWAIT) is notification-based on Darwin as well. A blocking
    // worker observes exit but leaves reaping and process-group ownership here.
    tokio::task::spawn_blocking(move || {
        rustix::process::waitid(
            rustix::process::WaitId::Pid(pid),
            rustix::process::WaitIdOptions::EXITED | rustix::process::WaitIdOptions::NOWAIT,
        )?;
        Ok::<_, io::Error>(())
    })
    .await
    .map_err(io::Error::other)?
}
/// Run with one deadline covering stdin, both output pipes, and child exit.
pub async fn run(
    command: &mut Command,
    input: Option<&[u8]>,
    deadline: Duration,
) -> io::Result<Output> {
    run_with_grace(command, input, deadline, Duration::ZERO).await
}
/// Give a failing child bounded TERM grace, then KILL all remaining group members.
/// Dropping this future also kills the group before Tokio reaps its leader.
pub async fn run_with_grace(
    command: &mut Command,
    input: Option<&[u8]>,
    deadline: Duration,
    grace: Duration,
) -> io::Result<Output> {
    command
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true)
        .process_group(0);
    let mut child = command.spawn()?;
    let pid = child
        .id()
        .and_then(|id| Pid::from_raw(id as i32))
        .ok_or_else(|| io::Error::other("child PID unavailable"))?;
    // Declared after child: cancellation drops this guard before the child owner.
    let mut group = Group { pid, armed: true };
    let mut stdin = child
        .stdin
        .take()
        .ok_or_else(|| io::Error::other("child stdin unavailable"))?;
    let mut stdout = child
        .stdout
        .take()
        .ok_or_else(|| io::Error::other("child stdout unavailable"))?;
    let mut stderr = child
        .stderr
        .take()
        .ok_or_else(|| io::Error::other("child stderr unavailable"))?;
    let observed = AtomicBool::new(false);
    let observer = async {
        let result = observe_exit(pid).await;
        // Completion includes errors: a completed async future must never be
        // polled again while cleaning up after a descriptor/observer failure.
        observed.store(true, Ordering::Relaxed);
        result
    };
    tokio::pin!(observer);
    let mut out = Vec::new();
    let mut err = Vec::new();
    let result = tokio::time::timeout(deadline, async {
        let write = async {
            if let Some(data) = input {
                stdin.write_all(data).await?;
            }
            drop(stdin);
            Ok::<_, io::Error>(())
        };
        tokio::try_join!(
            write,
            stdout.read_to_end(&mut out),
            stderr.read_to_end(&mut err),
            &mut observer
        )?;
        Ok::<_, io::Error>(())
    })
    .await;
    if !matches!(result, Ok(Ok(()))) && !grace.is_zero() {
        group.signal(Signal::TERM);
        if !observed.load(Ordering::Relaxed) {
            let _grace_result = tokio::time::timeout(grace, &mut observer).await;
        }
    }
    // The leader remains unreaped here even if it exited during TERM grace.
    // Always remove descendants, including those which closed inherited pipes.
    group.signal(Signal::KILL);
    let status = child.wait().await?;
    group.armed = false;
    match result {
        Ok(Ok(())) => Ok(Output {
            status,
            stdout: out,
            stderr: err,
        }),
        Ok(Err(error)) => Err(error),
        Err(_) => Err(io::Error::new(
            io::ErrorKind::TimedOut,
            "child deadline exceeded",
        )),
    }
}
