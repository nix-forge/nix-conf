#![forbid(unsafe_code)]
//! Descriptor-bound filesystem primitives for local-control.
//!
//! All path resolution is performed with `openat` from an already-open parent
//! descriptor.  This prevents a path component from being swapped for a
//! symlink between validation and use.

use std::{
    ffi::{OsStr, OsString},
    fs::File,
    io::{self, Read, Write},
    os::{
        fd::{AsRawFd, OwnedFd},
        unix::{ffi::OsStringExt, process::CommandExt},
    },
    path::{Component, Path, PathBuf},
    process::Command,
};

use rustix::{
    fs::{self, AtFlags, FileType, Mode, OFlags},
    io::Errno,
    process,
};

/// The expected type and access mode for a trusted descriptor.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ExpectedKind {
    /// A regular file.
    File,
    /// A directory.
    Directory,
}

/// A validated mode policy.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ExpectedMode {
    /// Group and other users must have no permissions.
    Private,
    /// The file mode must match exactly, including special bits.
    Exact(u32),
}

/// Errors returned by descriptor-bound operations.
#[derive(Debug)]
pub enum Error {
    /// The caller supplied an invalid or non-normalized path.
    InvalidPath(&'static str),
    /// A trusted object failed its ownership, type, or mode policy.
    UnsafePath(&'static str),
    /// A platform operation failed.
    Io(io::Error),
}

impl std::fmt::Display for Error {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidPath(message) | Self::UnsafePath(message) => formatter.write_str(message),
            Self::Io(error) => error.fmt(formatter),
        }
    }
}

impl std::error::Error for Error {}

impl From<io::Error> for Error {
    fn from(error: io::Error) -> Self {
        Self::Io(error)
    }
}

fn io_error(error: Errno) -> Error {
    Error::Io(error.into())
}

#[cfg(target_os = "macos")]
fn native_mode(mode: u32) -> Result<Mode, Error> {
    let raw_mode =
        u16::try_from(mode).map_err(|_| Error::InvalidPath("requested file mode is invalid"))?;
    Ok(Mode::from_raw_mode(raw_mode))
}

#[cfg(not(target_os = "macos"))]
fn native_mode(mode: u32) -> Result<Mode, Error> {
    Ok(Mode::from_raw_mode(mode))
}

fn open_root(path: &Path) -> Result<OwnedFd, Error> {
    let root = if path.is_absolute() {
        Path::new("/")
    } else {
        Path::new(".")
    };
    fs::open(root, directory_lookup_flags(), Mode::empty()).map_err(io_error)
}

fn normal_components(path: &Path) -> Result<Vec<OsString>, Error> {
    let mut components = Vec::new();
    for component in path.components() {
        match component {
            Component::RootDir | Component::CurDir => {}
            Component::Normal(name) => components.push(name.to_os_string()),
            Component::ParentDir | Component::Prefix(_) => {
                return Err(Error::InvalidPath(
                    "path must contain only normal components",
                ));
            }
        }
    }
    if components.is_empty() && path != Path::new(".") && path != Path::new("/") {
        return Err(Error::InvalidPath("path is empty"));
    }
    Ok(components)
}

fn directory_lookup_flags() -> OFlags {
    // macOS's O_SEARCH allows descriptor-bound traversal through a deliberate
    // execute-only parent (the nix-seal runtime root is 0711). Linux's O_PATH
    // has the equivalent lookup-only property. Other Unix targets retain the
    // portable, read-only directory fallback.
    #[cfg(target_os = "macos")]
    {
        OFlags::from_bits_retain(0x4010_0000)
            | OFlags::NOFOLLOW
            | OFlags::CLOEXEC
            | OFlags::NONBLOCK
    }
    #[cfg(target_os = "linux")]
    {
        OFlags::PATH | OFlags::DIRECTORY | OFlags::NOFOLLOW | OFlags::CLOEXEC | OFlags::NONBLOCK
    }
    #[cfg(not(any(target_os = "macos", target_os = "linux")))]
    {
        OFlags::RDONLY | OFlags::DIRECTORY | OFlags::CLOEXEC | OFlags::NOFOLLOW | OFlags::NONBLOCK
    }
}

fn directory_read_flags() -> OFlags {
    OFlags::RDONLY | OFlags::DIRECTORY | OFlags::CLOEXEC | OFlags::NOFOLLOW | OFlags::NONBLOCK
}

/// Opens `path` without following any symlink in its component chain.
///
/// `final_flags` is added to the final descriptor, permitting callers to
/// request read/write access or require a directory.  The returned descriptor
/// remains the authority for every subsequent operation.
pub fn open_trusted(path: &Path, final_flags: OFlags) -> Result<OwnedFd, Error> {
    open_trusted_internal(path, final_flags, false)
}

fn valid_generation_target(target: &[u8]) -> bool {
    target.starts_with(b"generation-")
        && target.len() > "generation-".len()
        && matches!(target["generation-".len()], b'1'..=b'9')
        && target["generation-".len() + 1..]
            .iter()
            .all(u8::is_ascii_digit)
}

fn open_trusted_internal(
    path: &Path,
    final_flags: OFlags,
    allow_generation_link: bool,
) -> Result<OwnedFd, Error> {
    if path.as_os_str().is_empty() {
        return Err(Error::InvalidPath("path is empty"));
    }
    let components = normal_components(path)?;
    if components.is_empty() {
        return fs::open(
            path,
            OFlags::RDONLY | OFlags::CLOEXEC | OFlags::NOFOLLOW | OFlags::NONBLOCK | final_flags,
            Mode::empty(),
        )
        .map_err(io_error);
    }
    let mut directory = open_root(path)?;

    let mut followed_generation_link = false;
    for (index, component) in components.iter().enumerate() {
        let final_component = index + 1 == components.len();
        let flags = if final_component {
            OFlags::RDONLY | OFlags::CLOEXEC | OFlags::NOFOLLOW | OFlags::NONBLOCK | final_flags
        } else {
            directory_lookup_flags()
        };
        let next = match fs::openat(&directory, component, flags, Mode::empty()) {
            Ok(descriptor) => descriptor,
            Err(Errno::LOOP | Errno::NOTDIR)
                if allow_generation_link
                    && !followed_generation_link
                    && !final_component
                    && component == OsStr::new("current") =>
            {
                let link = fs::statat(&directory, component, AtFlags::SYMLINK_NOFOLLOW)
                    .map_err(io_error)?;
                if FileType::from_raw_mode(link.st_mode) != FileType::Symlink
                    || link.st_uid != process::geteuid().as_raw()
                {
                    return Err(Error::UnsafePath("generation link is unsafe"));
                }
                let target = fs::readlinkat(&directory, component, Vec::new()).map_err(io_error)?;
                if !valid_generation_target(target.to_bytes()) {
                    return Err(Error::UnsafePath("generation link has an invalid target"));
                }
                let descriptor = fs::openat(
                    &directory,
                    target.as_ref(),
                    directory_lookup_flags(),
                    Mode::empty(),
                )
                .map_err(io_error)?;
                verify_descriptor(&descriptor, ExpectedKind::Directory, ExpectedMode::Private)?;
                followed_generation_link = true;
                descriptor
            }
            Err(error) => return Err(io_error(error)),
        };
        directory = next;
    }
    Ok(directory)
}

/// Opens a file through the narrowly scoped, owned `current -> generation-N`
/// symlink used by nix-seal's generation directory.
pub fn open_generation_file(path: &Path, expected_mode: ExpectedMode) -> Result<OwnedFd, Error> {
    let descriptor = open_trusted_internal(path, OFlags::empty(), true)?;
    verify_descriptor(&descriptor, ExpectedKind::File, expected_mode)?;
    Ok(descriptor)
}

fn verify_descriptor(
    descriptor: &OwnedFd,
    expected_kind: ExpectedKind,
    expected_mode: ExpectedMode,
) -> Result<fs::Stat, Error> {
    let metadata = fs::fstat(descriptor).map_err(io_error)?;
    let file_type = FileType::from_raw_mode(metadata.st_mode);
    match (expected_kind, file_type) {
        (ExpectedKind::File, FileType::RegularFile)
        | (ExpectedKind::Directory, FileType::Directory) => {}
        (ExpectedKind::File, _) => return Err(Error::UnsafePath("expected a real regular file")),
        (ExpectedKind::Directory, _) => return Err(Error::UnsafePath("expected a real directory")),
    }
    if metadata.st_uid != process::geteuid().as_raw() {
        return Err(Error::UnsafePath("path is not owned by the current user"));
    }
    let actual_mode = u32::from(metadata.st_mode & 0o7777);
    match expected_mode {
        ExpectedMode::Private if actual_mode & 0o077 != 0 => {
            return Err(Error::UnsafePath("path is accessible to group or others"));
        }
        ExpectedMode::Exact(expected) if actual_mode != expected => {
            return Err(Error::UnsafePath("path has an unexpected mode"));
        }
        ExpectedMode::Private | ExpectedMode::Exact(_) => {}
    }
    Ok(metadata)
}

/// Opens and validates a regular file without following symlinks.
pub fn open_file(path: &Path, expected_mode: ExpectedMode) -> Result<OwnedFd, Error> {
    let descriptor = open_trusted(path, OFlags::empty())?;
    verify_descriptor(&descriptor, ExpectedKind::File, expected_mode)?;
    Ok(descriptor)
}

/// Opens and validates a private directory without following symlinks.
pub fn open_private_directory(path: &Path) -> Result<OwnedFd, Error> {
    let descriptor = open_trusted(path, OFlags::DIRECTORY)?;
    verify_descriptor(&descriptor, ExpectedKind::Directory, ExpectedMode::Private)?;
    Ok(descriptor)
}

fn parent_and_leaf(path: &Path) -> Result<(PathBuf, OsString), Error> {
    let parent = path.parent().unwrap_or_else(|| Path::new("."));
    let leaf = path
        .file_name()
        .filter(|name| !name.is_empty() && *name != OsStr::new(".") && *name != OsStr::new(".."))
        .ok_or(Error::InvalidPath("path must name a file"))?;
    Ok((parent.to_path_buf(), leaf.to_os_string()))
}

/// Ensures that every component of `path` exists as a private directory.
pub fn ensure_private_directory(path: &Path) -> Result<(), Error> {
    if path.as_os_str().is_empty() {
        return Err(Error::InvalidPath("directory path is empty"));
    }
    let components = normal_components(path)?;
    let mut directory = open_root(path)?;
    let component_count = components.len();
    for (index, component) in components.into_iter().enumerate() {
        match fs::mkdirat(&directory, &component, Mode::from_raw_mode(0o700)) {
            Ok(()) | Err(Errno::EXIST) => {}
            Err(error) => return Err(io_error(error)),
        }
        let next = fs::openat(
            &directory,
            &component,
            directory_read_flags(),
            Mode::empty(),
        )
        .map_err(io_error)?;
        if index + 1 == component_count {
            verify_descriptor(&next, ExpectedKind::Directory, ExpectedMode::Private)?;
            fs::fchmod(&next, Mode::from_raw_mode(0o700)).map_err(io_error)?;
        }
        directory = next;
    }
    Ok(())
}

/// Reads a validated file and verifies that it did not change while being read.
pub fn read_file(path: &Path, expected_mode: ExpectedMode) -> Result<Vec<u8>, Error> {
    read_descriptor(open_file(path, expected_mode)?)
}

/// Reads a file resolved through the controlled generation link.
pub fn read_generation_file(path: &Path, expected_mode: ExpectedMode) -> Result<Vec<u8>, Error> {
    read_descriptor(open_generation_file(path, expected_mode)?)
}

fn read_descriptor(descriptor: OwnedFd) -> Result<Vec<u8>, Error> {
    let before = fs::fstat(&descriptor).map_err(io_error)?;
    let mut file = File::from(descriptor);
    let mut bytes = Vec::new();
    file.read_to_end(&mut bytes)?;
    let after = fs::fstat(&file).map_err(io_error)?;
    let expected_size =
        u64::try_from(before.st_size).map_err(|_| Error::UnsafePath("file has a negative size"))?;
    let actual_size = u64::try_from(bytes.len())
        .map_err(|_| Error::UnsafePath("file is too large to validate"))?;
    if !stat_matches(&before, &after) || actual_size != expected_size {
        return Err(Error::UnsafePath("file changed while it was being read"));
    }
    Ok(bytes)
}

/// Repairs the mode of an owned regular file without accepting a symlink.
pub fn repair_file_mode(path: &Path, mode: u32) -> Result<bool, Error> {
    let descriptor = match open_trusted(path, OFlags::RDWR) {
        Ok(descriptor) => descriptor,
        Err(Error::Io(error)) if error.kind() == io::ErrorKind::NotFound => return Ok(false),
        Err(error) => return Err(error),
    };
    let before = fs::fstat(&descriptor).map_err(io_error)?;
    if FileType::from_raw_mode(before.st_mode) != FileType::RegularFile {
        return Err(Error::UnsafePath("expected a real regular file"));
    }
    if before.st_uid != process::geteuid().as_raw() {
        return Err(Error::UnsafePath("path is not owned by the current user"));
    }
    fs::fchmod(&descriptor, native_mode(mode)?).map_err(io_error)?;
    let after = fs::fstat(&descriptor).map_err(io_error)?;
    if before.st_dev != after.st_dev
        || before.st_ino != after.st_ino
        || before.st_uid != after.st_uid
        || before.st_gid != after.st_gid
        || before.st_nlink != after.st_nlink
        || u32::from(after.st_mode & 0o7777) != mode
    {
        return Err(Error::UnsafePath(
            "file changed while its mode was being repaired",
        ));
    }
    Ok(true)
}

fn directory_entries(directory: &OwnedFd) -> Result<Vec<OsString>, Error> {
    let mut entries = Vec::new();
    let mut directory_reader = fs::Dir::read_from(directory).map_err(io_error)?;
    for entry in &mut directory_reader {
        let entry = entry.map_err(io_error)?;
        let name = OsString::from_vec(entry.file_name().to_bytes().to_vec());
        if name != OsStr::new(".") && name != OsStr::new("..") {
            entries.push(name);
        }
    }
    Ok(entries)
}

/// Returns whether a validated private directory contains no entries.
pub fn private_directory_is_empty(path: &Path) -> Result<bool, Error> {
    let directory = open_private_directory(path)?;
    Ok(directory_entries(&directory)?.is_empty())
}

/// Changes into a validated directory and replaces the process with `program`.
///
/// The command is intentionally an `exec`, exactly as a service wrapper needs:
/// no unvalidated pathname is retained as its current directory.
pub fn exec_in_directory(
    directory: &OwnedFd,
    program: &str,
    arguments: &[String],
) -> Result<(), Error> {
    process::fchdir(directory).map_err(io_error)?;
    let error = Command::new(program).args(arguments).exec();
    Err(Error::Io(error))
}

/// Validates and execs inside a private directory.
pub fn exec_private_directory(
    path: &Path,
    require_empty: bool,
    program: &str,
    arguments: &[String],
) -> Result<(), Error> {
    let directory = open_private_directory(path)?;
    if require_empty && !directory_entries(&directory)?.is_empty() {
        return Err(Error::UnsafePath("directory is not empty"));
    }
    exec_in_directory(&directory, program, arguments)
}

/// Validates and execs inside an owned source directory. Source trees need not
/// be private because they are immutable Nix inputs, but symlinks are still not
/// followed during resolution.
pub fn exec_source(path: &Path, program: &str, arguments: &[String]) -> Result<(), Error> {
    let directory = open_trusted(path, OFlags::DIRECTORY)?;
    verify_descriptor(&directory, ExpectedKind::Directory, ExpectedMode::Private).or_else(
        |_| {
            let metadata = fs::fstat(&directory).map_err(io_error)?;
            if FileType::from_raw_mode(metadata.st_mode) == FileType::Directory
                && metadata.st_uid == process::geteuid().as_raw()
            {
                Ok(metadata)
            } else {
                Err(Error::UnsafePath(
                    "source directory is not an owned real directory",
                ))
            }
        },
    )?;
    exec_in_directory(&directory, program, arguments)
}

/// Creates a new regular file from `contents`, failing if it already exists.
pub fn create_file(path: &Path, mode: u32, contents: &[u8]) -> Result<(), Error> {
    let (parent_path, leaf) = parent_and_leaf(path)?;
    let parent = open_private_directory(&parent_path)?;
    let descriptor = fs::openat(
        &parent,
        &leaf,
        OFlags::WRONLY | OFlags::CREATE | OFlags::EXCL | OFlags::CLOEXEC | OFlags::NOFOLLOW,
        native_mode(mode)?,
    )
    .map_err(io_error)?;
    let result = (|| {
        fs::fchmod(&descriptor, native_mode(mode)?).map_err(io_error)?;
        verify_descriptor(&descriptor, ExpectedKind::File, ExpectedMode::Exact(mode))?;
        let mut file = File::from(descriptor);
        file.write_all(contents)?;
        file.sync_all()?;
        Ok(())
    })();
    if result.is_err() {
        let _ = fs::unlinkat(&parent, &leaf, AtFlags::empty());
    }
    result
}

/// Replaces a validated file atomically with `contents` in the same directory.
pub fn atomic_write(path: &Path, mode: u32, contents: &[u8]) -> Result<(), Error> {
    let (parent_path, leaf) = parent_and_leaf(path)?;
    let parent = open_private_directory(&parent_path)?;
    match fs::openat(
        &parent,
        &leaf,
        OFlags::RDONLY | OFlags::CLOEXEC | OFlags::NOFOLLOW | OFlags::NONBLOCK,
        Mode::empty(),
    ) {
        Ok(existing) => {
            verify_descriptor(&existing, ExpectedKind::File, ExpectedMode::Exact(mode))?;
        }
        Err(Errno::NOENT) => {}
        Err(error) => return Err(io_error(error)),
    }

    let (temporary, descriptor) = open_temporary_file(&parent, mode)?;
    let result = (|| {
        fs::fchmod(&descriptor, native_mode(mode)?).map_err(io_error)?;
        let mut file = File::from(descriptor);
        file.write_all(contents)?;
        file.sync_all()?;
        fs::renameat(&parent, &temporary, &parent, &leaf).map_err(io_error)?;
        fs::fsync(&parent).map_err(io_error)
    })();
    if result.is_err() {
        let _ = fs::unlinkat(&parent, &temporary, AtFlags::empty());
    }
    result
}

fn open_temporary_file(parent: &OwnedFd, mode: u32) -> Result<(OsString, OwnedFd), Error> {
    let process_id = std::process::id();
    for attempt in 0..1000_u16 {
        let candidate = OsString::from(format!(".local-control.{process_id}.{attempt}"));
        match fs::openat(
            parent,
            &candidate,
            OFlags::WRONLY | OFlags::CREATE | OFlags::EXCL | OFlags::CLOEXEC | OFlags::NOFOLLOW,
            native_mode(mode)?,
        ) {
            Ok(descriptor) => return Ok((candidate, descriptor)),
            Err(Errno::EXIST) => {}
            Err(error) => return Err(io_error(error)),
        }
    }
    Err(Error::UnsafePath(
        "could not allocate a temporary file name",
    ))
}

fn stat_matches(before: &fs::Stat, after: &fs::Stat) -> bool {
    before.st_dev == after.st_dev
        && before.st_ino == after.st_ino
        && before.st_mode == after.st_mode
        && before.st_uid == after.st_uid
        && before.st_gid == after.st_gid
        && before.st_nlink == after.st_nlink
        && before.st_size == after.st_size
        && before.st_mtime == after.st_mtime
        && before.st_mtime_nsec == after.st_mtime_nsec
        && before.st_ctime == after.st_ctime
        && before.st_ctime_nsec == after.st_ctime_nsec
}

/// Parses an octal mode accepted by the command-line interface.
pub fn parse_mode(text: &str) -> Result<u32, Error> {
    let mode = u32::from_str_radix(text, 8)
        .map_err(|_| Error::InvalidPath("requested file mode is invalid"))?;
    if mode > 0o7777 {
        return Err(Error::InvalidPath("requested file mode is invalid"));
    }
    Ok(mode)
}

fn open_child_file(directory: &OwnedFd, name: &str, mode: ExpectedMode) -> Result<OwnedFd, Error> {
    let descriptor = fs::openat(
        directory,
        name,
        OFlags::RDONLY | OFlags::CLOEXEC | OFlags::NOFOLLOW | OFlags::NONBLOCK,
        Mode::empty(),
    )
    .map_err(io_error)?;
    verify_descriptor(&descriptor, ExpectedKind::File, mode)?;
    Ok(descriptor)
}

fn open_child_directory(directory: &OwnedFd, name: &str) -> Result<OwnedFd, Error> {
    let descriptor =
        fs::openat(directory, name, directory_read_flags(), Mode::empty()).map_err(io_error)?;
    verify_descriptor(&descriptor, ExpectedKind::Directory, ExpectedMode::Private)?;
    Ok(descriptor)
}

fn version_matches(contents: &[u8], version: &str) -> bool {
    contents == version.as_bytes()
        || contents
            .strip_suffix(b"\n")
            .is_some_and(|trimmed| trimmed == version.as_bytes())
}

/// Validates the minimal, security-relevant `PostgreSQL` cluster layout.
pub fn validate_cluster(directory: &OwnedFd, version: &str) -> Result<(), Error> {
    verify_descriptor(directory, ExpectedKind::Directory, ExpectedMode::Private)?;
    for name in [
        "PG_VERSION",
        "postgresql.conf",
        "pg_hba.conf",
        "pg_ident.conf",
    ] {
        open_child_file(directory, name, ExpectedMode::Private)?;
    }
    for name in ["base", "global", "pg_wal"] {
        open_child_directory(directory, name)?;
    }
    let version_file = open_child_file(directory, "PG_VERSION", ExpectedMode::Private)?;
    let contents = read_descriptor(version_file)?;
    if !version_matches(&contents, version) {
        return Err(Error::UnsafePath(
            "database directory has an incompatible version marker",
        ));
    }
    Ok(())
}

/// Reports the safe cluster state: `missing` for a genuinely empty directory,
/// `present` for a complete compatible cluster.
pub fn cluster_state(path: &Path, version: &str) -> Result<&'static str, Error> {
    let directory = open_private_directory(path)?;
    match open_child_file(&directory, "PG_VERSION", ExpectedMode::Private) {
        Ok(_) => {
            validate_cluster(&directory, version)?;
            Ok("present")
        }
        Err(Error::Io(error)) if error.kind() == io::ErrorKind::NotFound => {
            if directory_entries(&directory)?.is_empty() {
                Ok("missing")
            } else {
                Err(Error::UnsafePath(
                    "database directory is non-empty without a valid cluster marker",
                ))
            }
        }
        Err(error) => Err(error),
    }
}

/// Runs a database initializer inside a verified empty directory and validates
/// its result before returning.
pub fn initialize_cluster(
    path: &Path,
    version: &str,
    program: &str,
    arguments: &[String],
) -> Result<(), Error> {
    let directory = open_private_directory(path)?;
    if !directory_entries(&directory)?.is_empty() {
        return Err(Error::UnsafePath("database directory is not empty"));
    }
    process::fchdir(&directory).map_err(io_error)?;
    let status = Command::new(program)
        .args(arguments)
        .status()
        .map_err(Error::Io)?;
    if !status.success() {
        return Err(Error::UnsafePath("database initializer failed"));
    }
    validate_cluster(&directory, version)
}

/// Validates a `PostgreSQL` cluster and replaces the process with a command
/// whose current directory is the validated cluster root.
pub fn exec_cluster(
    path: &Path,
    version: &str,
    program: &str,
    arguments: &[String],
) -> Result<(), Error> {
    let directory = open_private_directory(path)?;
    validate_cluster(&directory, version)?;
    exec_in_directory(&directory, program, arguments)
}

/// Like [`exec_cluster`], but resolves a private socket directory by descriptor
/// and substitutes every `__LOCAL_CONTROL_SOCKET_PATH__` argument with that
/// resolved absolute path.
pub fn exec_cluster_socket(
    cluster_path: &Path,
    version: &str,
    socket_path: &Path,
    program: &str,
    arguments: &[String],
) -> Result<(), Error> {
    let cluster = open_private_directory(cluster_path)?;
    validate_cluster(&cluster, version)?;
    let socket = open_private_directory(socket_path)?;
    process::fchdir(&socket).map_err(io_error)?;
    let resolved_socket = std::env::current_dir().map_err(Error::Io)?;
    let resolved_socket = resolved_socket
        .to_str()
        .ok_or(Error::UnsafePath("socket path is not valid UTF-8"))?;
    let arguments = arguments
        .iter()
        .map(|argument| {
            if argument == "__LOCAL_CONTROL_SOCKET_PATH__" {
                resolved_socket.to_owned()
            } else {
                argument.clone()
            }
        })
        .collect::<Vec<_>>();
    exec_in_directory(&cluster, program, &arguments)
}

fn valid_leaf_name(name: &str) -> bool {
    !name.is_empty() && !name.contains('/') && name != "." && name != ".."
}

fn make_inheritable(descriptor: &OwnedFd) -> Result<(), Error> {
    let flags = rustix::io::fcntl_getfd(descriptor).map_err(io_error)?;
    rustix::io::fcntl_setfd(descriptor, flags & !rustix::io::FdFlags::CLOEXEC).map_err(io_error)
}

fn open_mapped_file(
    directory: &OwnedFd,
    name: &str,
    mode: u32,
    access: &str,
) -> Result<OwnedFd, Error> {
    if !valid_leaf_name(name) {
        return Err(Error::InvalidPath("mapped file specification is invalid"));
    }
    let (flags, created) = match access {
        "create" => (
            OFlags::RDWR
                | OFlags::CREATE
                | OFlags::EXCL
                | OFlags::CLOEXEC
                | OFlags::NOFOLLOW
                | OFlags::NONBLOCK,
            true,
        ),
        "update" => (
            OFlags::RDWR | OFlags::CLOEXEC | OFlags::NOFOLLOW | OFlags::NONBLOCK,
            false,
        ),
        "read" => (
            OFlags::RDONLY | OFlags::CLOEXEC | OFlags::NOFOLLOW | OFlags::NONBLOCK,
            false,
        ),
        _ => return Err(Error::InvalidPath("mapped file access is invalid")),
    };
    let descriptor = fs::openat(directory, name, flags, native_mode(mode)?).map_err(io_error)?;
    let result = (|| {
        if created {
            fs::fchmod(&descriptor, native_mode(mode)?).map_err(io_error)?;
        }
        verify_descriptor(&descriptor, ExpectedKind::File, ExpectedMode::Exact(mode))?;
        make_inheritable(&descriptor)
    })();
    if result.is_err() && created {
        let _ = fs::unlinkat(directory, name, AtFlags::empty());
    }
    result.map(|()| descriptor)
}

/// Opens named files beneath a private directory, maps them by inheritable
/// `/dev/fd/N` descriptors, and execs a child inside that directory.
pub fn exec_files(
    path: &Path,
    program: &str,
    specifications: &[(String, String, u32, String)],
    arguments: &[String],
) -> Result<(), Error> {
    let directory = open_private_directory(path)?;
    let mut mappings = Vec::with_capacity(specifications.len());
    for (access, name, mode, alias) in specifications {
        if mappings
            .iter()
            .any(|(existing, _): &(String, OwnedFd)| existing == alias)
        {
            return Err(Error::InvalidPath("mapped file name is duplicated"));
        }
        mappings.push((
            alias.clone(),
            open_mapped_file(&directory, name, *mode, access)?,
        ));
    }
    let replacements = arguments
        .iter()
        .map(|argument| {
            if let Some(alias) = argument
                .strip_prefix('@')
                .and_then(|rest| rest.strip_suffix('@'))
            {
                let (_, descriptor) = mappings
                    .iter()
                    .find(|(name, _)| name == alias)
                    .ok_or(Error::InvalidPath("mapped file placeholder is unknown"))?;
                Ok(format!("/dev/fd/{}", descriptor.as_raw_fd()))
            } else {
                Ok(argument.clone())
            }
        })
        .collect::<Result<Vec<_>, Error>>()?;
    exec_in_directory(&directory, program, &replacements)
}

fn load_proxy_secret(path: &Path, name: &str) -> Result<String, Error> {
    let contents = read_generation_file(path, ExpectedMode::Exact(0o600))?;
    if contents.is_empty() || contents.len() > 65_536 {
        return Err(Error::UnsafePath(
            "proxy environment file is empty, oversized, or unsafe",
        ));
    }
    let text = std::str::from_utf8(&contents)
        .map_err(|_| Error::UnsafePath("proxy environment file contains control data"))?;
    let mut found = None;
    for line in text.lines() {
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if line.contains('\r') {
            return Err(Error::UnsafePath(
                "proxy environment file contains control data",
            ));
        }
        let (key, value) = line.split_once('=').ok_or(Error::UnsafePath(
            "proxy environment file contains a malformed record",
        ))?;
        if !key.bytes().enumerate().all(|(index, byte)| {
            matches!(byte, b'A'..=b'Z' | b'_') || (index > 0 && byte.is_ascii_digit())
        }) {
            return Err(Error::UnsafePath(
                "proxy environment file contains a malformed record",
            ));
        }
        if key == name {
            if found.is_some()
                || !(32..=512).contains(&value.len())
                || !value.bytes().all(|byte| {
                    (0x21..=0x7e).contains(&byte) && !matches!(byte, b'"' | b'\\' | b'{' | b'}')
                })
            {
                return Err(Error::UnsafePath(
                    "proxy credential is missing, duplicated, or invalid",
                ));
            }
            found = Some(value.to_owned());
        }
    }
    found.ok_or(Error::UnsafePath(
        "proxy credential is missing, duplicated, or invalid",
    ))
}

/// Executes the proxy with descriptor-backed TLS material and the two
/// validated per-generation credentials.
pub fn exec_proxy(
    pki_directory: &Path,
    environment_file: &Path,
    program: &str,
    arguments: &[String],
) -> Result<(), Error> {
    let directory = open_private_directory(pki_directory)?;
    let mut files = Vec::new();
    for (name, mode) in [
        ("ca.crt", 0o644),
        ("server.crt", 0o644),
        ("server.key", 0o600),
    ] {
        let descriptor = open_mapped_file(&directory, name, mode, "read")?;
        files.push(descriptor);
    }
    let attestation = load_proxy_secret(environment_file, "SERVICE_PROXY_ATTESTATION")?;
    let browser_credential =
        load_proxy_secret(environment_file, "LOCAL_CONTROL_BROWSER_CREDENTIAL")?;
    process::fchdir(&directory).map_err(io_error)?;
    let mut command = Command::new(program);
    command.args(arguments);
    for (variable, descriptor) in [
        ("LOCAL_CONTROL_PROXY_CA", &files[0]),
        ("LOCAL_CONTROL_PROXY_CERT", &files[1]),
        ("LOCAL_CONTROL_PROXY_KEY", &files[2]),
    ] {
        command.env(variable, format!("/dev/fd/{}", descriptor.as_raw_fd()));
    }
    command.env("SERVICE_PROXY_ATTESTATION", attestation);
    command.env("LOCAL_CONTROL_BROWSER_CREDENTIAL", browser_credential);
    let error = command.exec();
    Err(Error::Io(error))
}

/// Creates a deterministic binary snapshot of an owned source tree.  The
/// stream is deliberately metadata-aware, excludes only a `.git` directory,
/// and rejects symlinks and special files.
pub fn snapshot_tree(path: &Path, output: &mut impl Write) -> Result<(), Error> {
    let directory = open_trusted(path, OFlags::DIRECTORY)?;
    let metadata = fs::fstat(&directory).map_err(io_error)?;
    if FileType::from_raw_mode(metadata.st_mode) != FileType::Directory
        || metadata.st_uid != process::geteuid().as_raw()
    {
        return Err(Error::UnsafePath(
            "source directory is not an owned real directory",
        ));
    }
    snapshot_directory(&directory, Path::new("."), output)
}

fn write_snapshot_record(
    output: &mut impl Write,
    kind: u8,
    mode: u32,
    path: &Path,
    contents: Option<&[u8]>,
) -> Result<(), Error> {
    let path = path.as_os_str().as_encoded_bytes();
    let size = contents.map_or(0_u64, |bytes| bytes.len() as u64);
    output.write_all(&[kind])?;
    output.write_all(&mode.to_le_bytes())?;
    output.write_all(&(path.len() as u64).to_le_bytes())?;
    output.write_all(path)?;
    output.write_all(&size.to_le_bytes())?;
    if let Some(contents) = contents {
        output.write_all(contents)?;
    }
    Ok(())
}

fn snapshot_directory(
    directory: &OwnedFd,
    path: &Path,
    output: &mut impl Write,
) -> Result<(), Error> {
    let before = fs::fstat(directory).map_err(io_error)?;
    let mut names = directory_entries(directory)?;
    names.sort_unstable();
    let after_entries = fs::fstat(directory).map_err(io_error)?;
    if !stat_matches(&before, &after_entries) {
        return Err(Error::UnsafePath(
            "source directory changed while it was being snapshotted",
        ));
    }
    write_snapshot_record(output, b'D', u32::from(before.st_mode & 0o7777), path, None)?;
    for name in names {
        let child = fs::openat(
            directory,
            &name,
            OFlags::RDONLY | OFlags::CLOEXEC | OFlags::NOFOLLOW | OFlags::NONBLOCK,
            Mode::empty(),
        )
        .map_err(io_error)?;
        let metadata = fs::fstat(&child).map_err(io_error)?;
        let kind = FileType::from_raw_mode(metadata.st_mode);
        let child_path = path.join(&name);
        if name == OsStr::new(".git") && kind == FileType::Directory {
            continue;
        }
        if metadata.st_uid != process::geteuid().as_raw() {
            return Err(Error::UnsafePath("source tree has an unowned entry"));
        }
        if kind == FileType::Directory {
            snapshot_directory(&child, &child_path, output)?;
        } else if kind == FileType::RegularFile {
            let contents = read_descriptor(child)?;
            write_snapshot_record(
                output,
                b'F',
                u32::from(metadata.st_mode & 0o7777),
                &child_path,
                Some(&contents),
            )?;
        } else {
            return Err(Error::UnsafePath(
                "source tree contains a symlink or special file",
            ));
        }
    }
    let after = fs::fstat(directory).map_err(io_error)?;
    if !stat_matches(&before, &after) {
        return Err(Error::UnsafePath(
            "source directory changed while it was being snapshotted",
        ));
    }
    Ok(())
}
