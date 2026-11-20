//! Bounded, descriptor-retaining ClamAV FILDES scans; never follow links.
use rustix::{
    event::{PollFd, PollFlags, poll},
    fs::{AtFlags, CWD, Dir, FileType, Mode, OFlags, fstat, openat, statat},
    net::{
        self, AddressFamily, SendAncillaryBuffer, SendAncillaryMessage, SendFlags, SocketAddrUnix,
        SocketFlags, SocketType,
    },
};
use std::{
    env, fs,
    io::{IoSlice, Read, Write},
    mem::MaybeUninit,
    os::{
        fd::{AsFd, OwnedFd},
        unix::{ffi::OsStrExt, net::UnixStream},
    },
    path::{Path, PathBuf},
    sync::atomic::{AtomicUsize, Ordering},
};
fn exchange(endpoint: &Path, fd: &OwnedFd) -> Result<(i32, String), Box<dyn std::error::Error>> {
    let socket = net::socket_with(
        AddressFamily::UNIX,
        SocketType::STREAM,
        SocketFlags::CLOEXEC | SocketFlags::NONBLOCK,
        None,
    )?;
    match net::connect(&socket, &SocketAddrUnix::new(endpoint)?) {
        Ok(()) => (),
        Err(
            rustix::io::Errno::INPROGRESS | rustix::io::Errno::ALREADY | rustix::io::Errno::INTR,
        ) => {
            loop {
                match poll(&mut [PollFd::new(&socket, PollFlags::OUT)], None) {
                    Err(rustix::io::Errno::INTR) => continue,
                    result => {
                        result?;
                        break;
                    }
                }
            }
            net::sockopt::socket_error(&socket)??;
        }
        Err(error) => return Err(error.into()),
    }
    net::getpeername(&socket)?;
    let mut socket = UnixStream::from(socket);
    socket.set_nonblocking(false)?;
    socket.write_all(b"zFILDES\0")?;
    let mut space = [MaybeUninit::uninit(); rustix::cmsg_space!(ScmRights(1))];
    let mut ancillary = SendAncillaryBuffer::new(&mut space);
    let fds = [fd.as_fd()];
    if !ancillary.push(SendAncillaryMessage::ScmRights(&fds)) {
        return Err("descriptor message does not fit".into());
    }
    if net::sendmsg(
        &socket,
        &[IoSlice::new(b"\0")],
        &mut ancillary,
        SendFlags::empty(),
    )? != 1
    {
        return Err("descriptor message was truncated".into());
    }
    let mut response = Vec::new();
    loop {
        let mut bytes = [0; 4096];
        let size = socket.read(&mut bytes)?;
        if size == 0 {
            return Ok((2, "daemon closed the connection before its reply".into()));
        }
        response.extend_from_slice(&bytes[..size]);
        if response.len() > 65536 {
            return Ok((2, "daemon reply exceeds the protocol limit".into()));
        }
        if let Some(end) = response.iter().position(|b| *b == 0) {
            if end + 1 != response.len() {
                return Ok((2, "unexpected data after the daemon reply".into()));
            }
            let message = String::from_utf8_lossy(&response[..end]).into_owned();
            return Ok(if message.ends_with(": OK") {
                (0, String::new())
            } else if message.ends_with(" FOUND") {
                (1, message)
            } else {
                (
                    2,
                    if message.is_empty() {
                        "empty daemon reply".into()
                    } else {
                        message
                    },
                )
            });
        }
    }
}
fn regular(directory: impl AsFd, name: &std::ffi::OsStr) -> rustix::io::Result<Option<OwnedFd>> {
    let info = match statat(&directory, name, AtFlags::SYMLINK_NOFOLLOW) {
        Err(rustix::io::Errno::NOENT) => return Ok(None),
        result => result?,
    };
    if FileType::from_raw_mode(info.st_mode) != FileType::RegularFile {
        return Ok(None);
    }
    let fd = match openat(
        &directory,
        name,
        OFlags::RDONLY | OFlags::CLOEXEC | OFlags::NOFOLLOW | OFlags::NONBLOCK,
        Mode::empty(),
    ) {
        Err(rustix::io::Errno::NOENT | rustix::io::Errno::LOOP) => return Ok(None),
        Err(error @ (rustix::io::Errno::NXIO | rustix::io::Errno::NODEV)) => {
            match statat(&directory, name, AtFlags::SYMLINK_NOFOLLOW) {
                Err(rustix::io::Errno::NOENT) => return Ok(None),
                Ok(m) if FileType::from_raw_mode(m.st_mode) != FileType::RegularFile => {
                    return Ok(None);
                }
                _ => return Err(error),
            }
        }
        result => result?,
    };
    Ok(
        if FileType::from_raw_mode(fstat(&fd)?.st_mode) == FileType::RegularFile {
            Some(fd)
        } else {
            None
        },
    )
}
// Python repr-style quoting keeps newlines in filenames from forging output rows.
fn quoted(path: &Path) -> String {
    let value = path.to_string_lossy();
    let quote = if value.contains('\'') && !value.contains('"') {
        '"'
    } else {
        '\''
    };
    let mut output = quote.to_string();
    for c in value.chars() {
        match c {
            '\\' => output.push_str("\\\\"),
            '\n' => output.push_str("\\n"),
            '\r' => output.push_str("\\r"),
            '\t' => output.push_str("\\t"),
            c if c == quote => {
                output.push('\\');
                output.push(c);
            }
            c if c.is_control() => output.push_str(&format!("\\x{:02x}", c as u32)),
            c => output.push(c),
        }
    }
    output.push(quote);
    output
}
struct Scanner {
    endpoint: PathBuf,
    workers: usize,
    result: i32,
    batch: Vec<(PathBuf, OwnedFd)>,
}
impl Scanner {
    fn failure(&mut self, error: impl std::fmt::Display) {
        self.result = 2;
        eprintln!("ERROR: {error}");
    }
    fn flush(&mut self) {
        let index = AtomicUsize::new(0);
        let results = std::thread::scope(|scope| {
            let mut threads = Vec::new();
            for _ in 0..self.workers.min(self.batch.len()) {
                let index = &index;
                let batch = &self.batch;
                let endpoint = &self.endpoint;
                threads.push(scope.spawn(move || {
                    let mut replies = Vec::new();
                    loop {
                        let i = index.fetch_add(1, Ordering::Relaxed);
                        if i >= batch.len() {
                            break;
                        }
                        let reply =
                            exchange(endpoint, &batch[i].1).unwrap_or_else(|e| (2, e.to_string()));
                        replies.push((i, reply));
                    }
                    replies
                }));
            }
            let mut replies = Vec::new();
            for thread in threads {
                match thread.join() {
                    Ok(rows) => replies.extend(rows),
                    Err(_) => replies.push((usize::MAX, (2, "scan worker failed".into()))),
                }
            }
            replies.sort_by_key(|r| r.0);
            replies
        });
        for (index, (status, message)) in results {
            self.result = self.result.max(status);
            if !message.is_empty() {
                if let Some((path, _)) = self.batch.get(index) {
                    println!("{}: {message}", quoted(path));
                } else {
                    self.failure(message);
                }
            }
        }
        self.batch.clear();
    }
    fn enqueue(&mut self, path: PathBuf, directory: impl AsFd, name: &std::ffi::OsStr) {
        match regular(directory, name) {
            Ok(Some(fd)) => self.batch.push((path, fd)),
            Ok(None) => (),
            Err(error) => self.failure(error),
        }
        if self.batch.len() == 128 {
            self.flush();
        }
    }
    fn walk(&mut self, path: &Path, fd: &OwnedFd) {
        let entries = match Dir::read_from(fd) {
            Ok(entries) => entries,
            Err(error) => {
                self.failure(error);
                return;
            }
        };
        for entry in entries {
            let entry = match entry {
                Ok(e) => e,
                Err(error) => {
                    self.failure(error);
                    continue;
                }
            };
            let name = std::ffi::OsStr::from_bytes(entry.file_name().to_bytes());
            if name == "." || name == ".." {
                continue;
            }
            let child = path.join(name);
            let info = match statat(fd, name, AtFlags::SYMLINK_NOFOLLOW) {
                Ok(info) => info,
                Err(rustix::io::Errno::NOENT) => continue,
                Err(error) => {
                    self.failure(error);
                    continue;
                }
            };
            if FileType::from_raw_mode(info.st_mode) == FileType::Directory {
                match openat(
                    fd,
                    name,
                    OFlags::RDONLY | OFlags::DIRECTORY | OFlags::NOFOLLOW | OFlags::CLOEXEC,
                    Mode::empty(),
                ) {
                    Ok(next) => self.walk(&child, &next),
                    Err(
                        rustix::io::Errno::NOENT
                        | rustix::io::Errno::LOOP
                        | rustix::io::Errno::NOTDIR,
                    ) => (),
                    Err(error) => self.failure(error),
                }
            } else {
                self.enqueue(child, fd, name);
            }
        }
    }
    fn root(&mut self, root: &Path) {
        match fs::symlink_metadata(root) {
            Ok(info) if info.is_file() => self.enqueue(root.into(), CWD, root.as_os_str()),
            Ok(info) if info.is_dir() => match openat(
                CWD,
                root,
                OFlags::RDONLY | OFlags::DIRECTORY | OFlags::NOFOLLOW | OFlags::CLOEXEC,
                Mode::empty(),
            ) {
                Ok(fd) => self.walk(root, &fd),
                Err(error) => self.failure(error),
            },
            Ok(_) => (),
            Err(error) => self.failure(error),
        }
    }
}
fn main() {
    let mut arguments = env::args_os().skip(1);
    let mut args = Vec::new();
    let mut workers = 1;
    let mut positional = false;
    while let Some(arg) = arguments.next() {
        if !positional && (arg == "--help" || arg == "-h") {
            println!("Usage: clamav-scan-regular-files [--workers N] socket roots...");
            return;
        }
        if !positional && arg == "--" {
            positional = true;
            continue;
        }
        let value = if !positional && arg == "--workers" {
            Some(arguments.next().unwrap_or_default())
        } else if !positional && arg.as_bytes().starts_with(b"--workers=") {
            Some(std::ffi::OsStr::from_bytes(&arg.as_bytes()[10..]).to_owned())
        } else {
            None
        };
        if let Some(value) = value {
            workers = value
                .to_str()
                .and_then(|s| s.parse::<usize>().ok())
                .unwrap_or(0);
            if workers == 0 {
                eprintln!("worker count must be positive");
                std::process::exit(2);
            }
            continue;
        }
        if !positional && arg.as_bytes().starts_with(b"-") {
            eprintln!("unrecognized option");
            std::process::exit(2);
        }
        args.push(arg);
    }
    if args.len() < 2 || workers == 0 {
        eprintln!("expected [--workers N] socket roots; worker count must be positive");
        std::process::exit(2);
    }
    let mut scanner = Scanner {
        endpoint: PathBuf::from(&args[0]),
        workers,
        result: 0,
        batch: Vec::new(),
    };
    for path in &args[1..] {
        scanner.root(Path::new(path));
    }
    scanner.flush();
    std::process::exit(scanner.result);
}
