//! Signal cleanup owns temporary paths, terminal state and unreaped child groups.
use rustix::process::{Pid, Signal, kill_process_group};
use std::{
    ffi::OsStr,
    fs,
    io::{self, Read, Write},
    os::unix::{fs::MetadataExt, process::CommandExt},
    path::{Path, PathBuf},
    process::{Child, ExitStatus, Output, Stdio},
    sync::{Mutex, MutexGuard},
};
enum Resource {
    Path(PathBuf, Option<(u64, u64)>),
    Child(Pid, bool),
    Terminal(rustix::termios::Termios),
}
struct State {
    next: u64,
    entries: Vec<(u64, Resource)>,
}
static STATE: Mutex<State> = Mutex::new(State {
    next: 0,
    entries: Vec::new(),
});
fn state() -> MutexGuard<'static, State> {
    STATE.lock().unwrap_or_else(|error| error.into_inner())
}
fn cleanup(resource: &Resource) {
    match resource {
        Resource::Path(path, identity) => {
            if let Ok(m) = fs::symlink_metadata(path)
                && m.is_file()
                && identity.is_none_or(|key| key == (m.dev(), m.ino()))
            {
                let _cleanup_result = fs::remove_file(path);
            }
        }
        Resource::Child(pid, _) => {
            let _signal_result = kill_process_group(*pid, Signal::KILL);
        }
        Resource::Terminal(original) => {
            let _restore_result = rustix::termios::tcsetattr(
                io::stdin(),
                rustix::termios::OptionalActions::Now,
                original,
            );
        }
    }
}
pub struct Guard(u64);
fn register(state: &mut State, resource: Resource) -> Guard {
    let id = state.next;
    state.next += 1;
    state.entries.push((id, resource));
    Guard(id)
}
impl Drop for Guard {
    fn drop(&mut self) {
        let mut state = state();
        if let Some(index) = state.entries.iter().position(|(id, _)| *id == self.0) {
            let (_, resource) = state.entries.swap_remove(index);
            cleanup(&resource);
        }
    }
}
pub fn signals() -> io::Result<()> {
    use signal_hook::{
        consts::{SIGHUP, SIGINT, SIGQUIT, SIGTERM},
        iterator::Signals,
    };
    let mut signals = Signals::new([SIGHUP, SIGINT, SIGQUIT, SIGTERM])?;
    std::thread::spawn(move || {
        if let Some(signal) = signals.forever().next() {
            let state = state();
            for (_, resource) in state.entries.iter().rev() {
                if let Resource::Child(pid, cooperative) = resource {
                    // Nested native controllers also own cleanup. Notify them,
                    // then wait on the unreaped leader before the final group kill.
                    let _signal_result = kill_process_group(*pid, Signal::TERM);
                    if *cooperative {
                        // A recursive controller owns its own groups and temporary
                        // paths. Await its cleanup acknowledgement (exit), rather
                        // than racing an independent outer hard-kill deadline.
                        while let Err(rustix::io::Errno::INTR) = rustix::process::waitid(
                            rustix::process::WaitId::Pid(*pid),
                            rustix::process::WaitIdOptions::EXITED
                                | rustix::process::WaitIdOptions::NOWAIT,
                        ) {}
                    } else if let Ok(fd) =
                        rustix::process::pidfd_open(*pid, rustix::process::PidfdFlags::empty())
                    {
                        let mut descriptors = [rustix::event::PollFd::new(
                            &fd,
                            rustix::event::PollFlags::IN,
                        )];
                        let _wait_result = rustix::event::poll(
                            &mut descriptors,
                            Some(&rustix::event::Timespec {
                                tv_sec: 2,
                                tv_nsec: 0,
                            }),
                        );
                    }
                }
                cleanup(resource);
            } // Hold the lock until exit: no spawn/publication can race cancellation.
            std::process::exit(128 + signal);
        }
    });
    Ok(())
}
pub fn terminal(original: rustix::termios::Termios) -> Guard {
    register(&mut state(), Resource::Terminal(original))
}
pub fn candidate(path: &str) -> Guard {
    register(&mut state(), Resource::Path(path.into(), None))
}
pub fn temporary(parent: Option<&Path>) -> io::Result<(tempfile::NamedTempFile, Guard)> {
    let mut state = state();
    let file = if let Some(parent) = parent {
        tempfile::NamedTempFile::new_in(parent)?
    } else {
        tempfile::NamedTempFile::new()?
    };
    let metadata = file.as_file().metadata()?;
    let guard = register(
        &mut state,
        Resource::Path(file.path().into(), Some((metadata.dev(), metadata.ino()))),
    );
    Ok((file, guard))
}
struct OwnedChild {
    child: Child,
    guard: Option<Guard>,
}
impl OwnedChild {
    fn wait(&mut self) -> io::Result<ExitStatus> {
        let pid = Pid::from_raw(i32::try_from(self.child.id()).map_err(io::Error::other)?)
            .ok_or_else(|| io::Error::other("invalid child ID"))?;
        loop {
            match rustix::process::waitid(
                rustix::process::WaitId::Pid(pid),
                rustix::process::WaitIdOptions::EXITED | rustix::process::WaitIdOptions::NOWAIT,
            ) {
                Err(rustix::io::Errno::INTR) => continue,
                Err(e) => return Err(e.into()),
                Ok(_) => break,
            }
        }
        // Kill remaining descendants while the leader still reserves the PGID.
        drop(self.guard.take());
        self.child.wait()
    }
}
impl Drop for OwnedChild {
    fn drop(&mut self) {
        drop(self.guard.take());
        let _reap_result = self.child.wait();
    }
}
pub struct Command {
    inner: std::process::Command,
    stdin: bool,
    stdout: bool,
    stderr: bool,
    cooperative: bool,
}
impl Command {
    pub fn new(tool: impl AsRef<OsStr>) -> Self {
        Self {
            inner: std::process::Command::new(tool),
            stdin: false,
            stdout: false,
            stderr: false,
            cooperative: false,
        }
    }
    pub fn cooperative(&mut self) -> &mut Self {
        self.cooperative = true;
        self
    }
    pub fn arg(&mut self, arg: impl AsRef<OsStr>) -> &mut Self {
        self.inner.arg(arg);
        self
    }
    pub fn args<I, S>(&mut self, args: I) -> &mut Self
    where
        I: IntoIterator<Item = S>,
        S: AsRef<OsStr>,
    {
        self.inner.args(args);
        self
    }
    pub fn env(&mut self, key: impl AsRef<OsStr>, value: impl AsRef<OsStr>) -> &mut Self {
        self.inner.env(key, value);
        self
    }
    pub fn env_remove(&mut self, key: impl AsRef<OsStr>) -> &mut Self {
        self.inner.env_remove(key);
        self
    }
    pub fn stdin(&mut self, stdio: impl Into<Stdio>) -> &mut Self {
        self.inner.stdin(stdio);
        self.stdin = true;
        self
    }
    pub fn stdout(&mut self, stdio: impl Into<Stdio>) -> &mut Self {
        self.inner.stdout(stdio);
        self.stdout = true;
        self
    }
    pub fn stderr(&mut self, stdio: impl Into<Stdio>) -> &mut Self {
        self.inner.stderr(stdio);
        self.stderr = true;
        self
    }
    fn spawn(&mut self) -> io::Result<OwnedChild> {
        let mut state = state();
        let child = self.inner.process_group(0).spawn()?;
        let pid = Pid::from_raw(i32::try_from(child.id()).map_err(io::Error::other)?)
            .ok_or_else(|| io::Error::other("invalid child ID"))?;
        let guard = register(&mut state, Resource::Child(pid, self.cooperative));
        Ok(OwnedChild {
            child,
            guard: Some(guard),
        })
    }
    pub fn status(&mut self) -> io::Result<ExitStatus> {
        self.spawn()?.wait()
    }
    pub fn output(&mut self) -> io::Result<Output> {
        self.output_with_input(None)
    }
    pub fn output_with_input(&mut self, input: Option<&[u8]>) -> io::Result<Output> {
        if input.is_some() {
            self.stdin(Stdio::piped());
        } else if !self.stdin {
            self.stdin(Stdio::null());
        }
        if !self.stdout {
            self.stdout(Stdio::piped());
        }
        if !self.stderr {
            self.stderr(Stdio::piped());
        }
        let mut child = self.spawn()?;
        fn reader(
            pipe: Option<impl Read + Send + 'static>,
        ) -> std::thread::JoinHandle<io::Result<Vec<u8>>> {
            std::thread::spawn(move || {
                let mut bytes = Vec::new();
                if let Some(mut pipe) = pipe {
                    pipe.read_to_end(&mut bytes)?;
                }
                Ok(bytes)
            })
        }
        let stdout = reader(child.child.stdout.take());
        let stderr = reader(child.child.stderr.take());
        if let Some(input) = input {
            child
                .child
                .stdin
                .take()
                .ok_or_else(|| io::Error::other("child stdin missing"))?
                .write_all(input)?;
        }
        let status = child.wait()?;
        let stdout = stdout
            .join()
            .map_err(|_| io::Error::other("stdout observer failed"))??;
        let stderr = stderr
            .join()
            .map_err(|_| io::Error::other("stderr observer failed"))??;
        Ok(Output {
            status,
            stdout,
            stderr,
        })
    }
    pub fn exec(&mut self) -> io::Error {
        self.inner.exec()
    }
    // Explicit UI launch outlives this invocation, as in the original CLI.
    pub fn spawn_detached(&mut self) -> io::Result<Child> {
        self.inner.spawn()
    }
}
