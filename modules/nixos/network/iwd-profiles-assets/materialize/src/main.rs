//! Copy private runtime credentials using IWD's byte-based filename encoding.
use std::{
    env,
    fs::{self, File, Permissions},
    io::Write,
    os::unix::fs::{DirBuilderExt, MetadataExt, PermissionsExt},
    path::Path,
    process::{Command, Stdio},
};

fn provision(args: &[std::ffi::OsString]) -> Result<(), Box<dyn std::error::Error>> {
    if args.len() != 4 {
        return Err("expected source directory validator profile_type".into());
    }
    let kind = args[3].to_str().ok_or("invalid profile type")?;
    if !["psk", "8021x", "open"].contains(&kind) {
        return Err("invalid profile type".into());
    }
    let source = fs::canonicalize(&args[0])?;
    let info = fs::metadata(&source)?;
    let uid = rustix::process::geteuid().as_raw();
    if !info.is_file()
        || source.starts_with("/nix/store")
        || info.uid() != uid
        || info.mode() & 0o077 != 0
    {
        return Err("unprotected source".into());
    }
    let bytes = fs::read(source)?;
    let newline = bytes
        .iter()
        .position(|b| *b == b'\n')
        .ok_or("missing header")?;
    let header = bytes[..newline]
        .strip_suffix(b"\r")
        .unwrap_or(&bytes[..newline]);
    let ssid = header.strip_prefix(b"SSID=").ok_or("missing SSID")?;
    if ssid.is_empty() || ssid.len() > 32 || ssid.contains(&0) {
        return Err("invalid SSID".into());
    }
    std::str::from_utf8(ssid)?;
    let body = &bytes[newline + 1..];
    std::str::from_utf8(body)?;
    if body.contains(&0) {
        return Err("invalid profile".into());
    }
    let name = if ssid
        .iter()
        .all(|b| b.is_ascii_alphanumeric() || b" _-".contains(b))
    {
        String::from_utf8(ssid.to_vec())?
    } else {
        format!(
            "={}",
            ssid.iter().map(|b| format!("{b:02x}")).collect::<String>()
        )
    };
    let mut validator = Command::new(&args[2])
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()?;
    let written = validator
        .stdin
        .take()
        .ok_or("missing validator input")?
        .write_all(body);
    let status = validator.wait()?;
    written?;
    if !status.success() {
        return Err("invalid profile".into());
    }
    let directory = Path::new(&args[1]);
    fs::DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(directory)?;
    if fs::metadata(directory)?.uid() != uid {
        return Err("unowned directory".into());
    }
    fs::set_permissions(directory, Permissions::from_mode(0o700))?;
    let destination = directory.join(format!("{name}.{kind}"));
    if fs::symlink_metadata(&destination).is_ok_and(|m| m.is_file())
        && fs::read(&destination)? == body
    {
        fs::set_permissions(destination, Permissions::from_mode(0o600))?;
        return Ok(());
    }
    let mut temporary = tempfile::Builder::new()
        .prefix(".iwd-profile-")
        .tempfile_in(directory)?;
    temporary.write_all(body)?;
    temporary.as_file().sync_all()?;
    temporary.persist(destination).map_err(|e| e.error)?;
    File::open(directory)?.sync_all()?;
    Ok(())
}
fn main() {
    if provision(&env::args_os().skip(1).collect::<Vec<_>>()).is_err() {
        eprintln!("Unable to install the protected IWD profile.");
        std::process::exit(1);
    }
}
