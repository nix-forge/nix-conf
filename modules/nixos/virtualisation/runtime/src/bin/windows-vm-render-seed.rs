//! Render volatile installer credentials without exposing them in diagnostics.
use std::{
    collections::HashMap,
    env, fs,
    io::Write,
    os::unix::fs::{DirBuilderExt, PermissionsExt},
    path::Path,
};
const TOKEN: &str = "__WINDOWS_ADMINISTRATOR_PASSWORD_XML__";
fn atomic(path: &Path, bytes: &[u8]) -> Result<(), Box<dyn std::error::Error>> {
    let parent = path
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    fs::DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(parent)?;
    let mut file = tempfile::Builder::new()
        .prefix(&format!(
            ".{}.",
            path.file_name()
                .ok_or("missing file name")?
                .to_string_lossy()
        ))
        .tempfile_in(parent)?;
    file.as_file()
        .set_permissions(fs::Permissions::from_mode(0o600))?;
    file.write_all(bytes)?;
    file.as_file().sync_all()?;
    file.persist(path).map_err(|e| e.error)?;
    Ok(())
}
fn run() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<_> = env::args_os().skip(1).collect();
    if args.len() != 8 {
        return Err("expected four named paths".into());
    }
    let mut options = HashMap::new();
    for pair in args.as_chunks::<2>().0 {
        let key = pair[0].to_str().ok_or("invalid option")?;
        if ![
            "--template",
            "--answer-file",
            "--credential-file",
            "--password-file",
        ]
        .contains(&key)
            || options.insert(key, Path::new(&pair[1])).is_some()
        {
            return Err("invalid option".into());
        }
    }
    let path = *options.get("--password-file").ok_or("missing password")?;
    let info = fs::symlink_metadata(path)?;
    if !info.is_file() || info.permissions().mode() & 0o077 != 0 {
        return Err("password input must be a private regular file".into());
    }
    let secret = fs::read_to_string(path)?;
    let password = secret.strip_suffix('\n').unwrap_or(&secret);
    if password.len() < 16
        || !password
            .as_bytes()
            .first()
            .is_some_and(u8::is_ascii_alphanumeric)
        || !password.bytes().all(|b| (0x21..=0x7e).contains(&b))
    {
        return Err("invalid password format".into());
    }
    let categories = [
        password.bytes().any(|b| b.is_ascii_lowercase()),
        password.bytes().any(|b| b.is_ascii_uppercase()),
        password.bytes().any(|b| b.is_ascii_digit()),
        password.bytes().any(|b| !b.is_ascii_alphanumeric()),
    ];
    if categories.iter().filter(|b| **b).count() < 3 {
        return Err("password must use at least three character categories".into());
    }
    let source = fs::read_to_string(options["--template"])?;
    if source.matches(TOKEN).count() != 2 {
        return Err("answer template must contain the password token twice".into());
    }
    let escaped = password
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;");
    let rendered = source.replace(TOKEN, &escaped);
    roxmltree::Document::parse(&rendered).map_err(|_| "invalid answer XML")?;
    atomic(options["--answer-file"], rendered.as_bytes())?;
    atomic(
        options["--credential-file"],
        format!("{password}\n").as_bytes(),
    )?;
    Ok(())
}
fn main() {
    if let Err(error) = run() {
        eprintln!("windows-vm-render-seed: {error}");
        std::process::exit(1);
    }
}
