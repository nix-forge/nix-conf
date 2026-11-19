//! Repair remembered desktop paths after generation changes, as the greeter UID.
use std::{
    env,
    error::Error,
    fs,
    io::{self, Write},
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    process::ExitCode,
};
fn resolve(root: &Path, name: &Path) -> Option<PathBuf> {
    let name = name.file_name()?;
    ["wayland-sessions", "xsessions"]
        .into_iter()
        .map(|directory| root.join("share").join(directory).join(name))
        .find(|path| path.is_file())
}
fn nonempty(path: &Path) -> bool {
    fs::metadata(path).is_ok_and(|m| m.len() != 0)
}
fn write(path: &Path, value: &[u8]) -> Result<(), Box<dyn Error>> {
    match fs::symlink_metadata(path) {
        Ok(m) if !m.is_file() => return Err("remembered cache must be a regular file".into()),
        Err(e) if e.kind() != io::ErrorKind::NotFound => return Err(e.into()),
        _ => (),
    }
    let mut file = tempfile::NamedTempFile::new_in(path.parent().ok_or("cache parent missing")?)?;
    file.as_file()
        .set_permissions(fs::Permissions::from_mode(0o644))?;
    file.write_all(value)?;
    file.as_file().sync_all()?;
    file.persist(path)?;
    Ok(())
}
fn run() -> Result<(), Box<dyn Error>> {
    let args: Vec<_> = env::args_os().skip(1).collect();
    if args.len() < 3 {
        return Err("usage: prepare-tuigreet-cache CACHE SESSION_ROOT DEFAULT [USERS...]".into());
    }
    let cache = Path::new(&args[0]);
    let root = Path::new(&args[1]);
    fs::create_dir_all(cache)?;
    let default =
        resolve(root, Path::new(&args[2])).ok_or("default desktop entry is unavailable")?;
    for user in &args[3..] {
        let name = user.to_str().ok_or("username is not UTF-8")?;
        if name.is_empty() || name.contains('/') || name == "." || name == ".." {
            return Err("invalid cache username".into());
        }
        let path = cache.join(format!("lastsession-path-{name}"));
        if fs::symlink_metadata(&path).is_err_and(|e| e.kind() == io::ErrorKind::NotFound)
            && nonempty(&cache.join(format!("lastsession-{name}")))
        {
            continue;
        }
        let saved = match fs::symlink_metadata(&path) {
            Ok(m) if m.is_file() => fs::read_to_string(&path)?,
            Ok(_) => return Err("remembered cache must be a regular file".into()),
            Err(e) if e.kind() == io::ErrorKind::NotFound => String::new(),
            Err(e) => return Err(e.into()),
        };
        let selected = resolve(root, Path::new(saved.trim_end_matches('\n')))
            .unwrap_or_else(|| default.clone());
        write(&path, selected.as_os_str().as_encoded_bytes())?;
    }
    let last = cache.join("lastuser");
    if !nonempty(&last) && args.len() == 4 {
        write(&last, args[3].as_encoded_bytes())?;
    }
    for entry in fs::read_dir(cache)? {
        let entry = entry?;
        if entry.file_name().as_encoded_bytes().starts_with(b"last") && entry.file_type()?.is_file()
        {
            fs::set_permissions(entry.path(), fs::Permissions::from_mode(0o644))?;
        }
    }
    Ok(())
}
fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("prepare-tuigreet-cache: {e}");
            ExitCode::FAILURE
        }
    }
}
