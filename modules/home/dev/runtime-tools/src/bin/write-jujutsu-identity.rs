//! Install a runtime-only identity without printing private Git diagnostics.
use std::{
    error::Error,
    fs,
    io::Write,
    os::unix::fs::{MetadataExt, PermissionsExt, symlink},
    path::{Path, PathBuf},
    time::Duration,
};
type Result<T> = std::result::Result<T, Box<dyn Error>>;
fn private_parent(destination: &Path) -> Result<&Path> {
    let parent = destination
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    fs::create_dir_all(parent)?;
    fs::set_permissions(parent, fs::Permissions::from_mode(0o700))?;
    Ok(parent)
}
async fn git_identity(git: &std::ffi::OsStr, field: &str) -> Result<String> {
    let result = nix_conf_process::run(
        tokio::process::Command::new(git).args([
            "config",
            "--global",
            "--includes",
            "--get",
            &format!("user.{field}"),
        ]),
        None,
        Duration::from_secs(30),
    )
    .await?;
    if result.status.code() == Some(1) {
        return Ok(String::new());
    }
    if !result.status.success() {
        return Err("Git identity unavailable".into());
    }
    let text = String::from_utf8(result.stdout)?;
    Ok(text.strip_suffix('\n').unwrap_or(&text).to_owned())
}
async fn run() -> Result<()> {
    let mut args = std::env::args_os().skip(1);
    let mut source = None;
    let mut git = None;
    let mut destination = None;
    while let Some(arg) = args.next() {
        match arg.to_str() {
            Some("--git") => {
                if git.is_some() {
                    return Err("duplicate mode".into());
                }
                git = Some(args.next().ok_or("missing Git executable")?);
            }
            Some("--source") => {
                if source.is_some() {
                    return Err("duplicate mode".into());
                }
                source = Some(PathBuf::from(args.next().ok_or("missing source")?));
            }
            _ => {
                if destination.replace(PathBuf::from(arg)).is_some() {
                    return Err("unexpected argument".into());
                }
            }
        }
    }
    let destination = destination.ok_or("destination required")?;
    match (source, git) {
        (Some(source), None) => {
            let resolved = source.canonicalize()?;
            let meta = fs::metadata(&resolved)?;
            if !meta.is_file()
                || resolved.starts_with("/nix/store")
                || ![0, rustix::process::getuid().as_raw()].contains(&meta.uid())
                || meta.mode() & 0o077 != 0
            {
                return Err("unprotected source".into());
            }
            let identity: toml::Table = toml::from_str(&fs::read_to_string(&resolved)?)?;
            let user = identity
                .get("user")
                .and_then(toml::Value::as_table)
                .ok_or("invalid identity")?;
            if identity.len() != 1
                || user.len() != 2
                || ["name", "email"].iter().any(|key| {
                    !user
                        .get(*key)
                        .and_then(toml::Value::as_str)
                        .is_some_and(|s| !s.is_empty())
                })
            {
                return Err("invalid identity".into());
            }
            let parent = private_parent(&destination)?;
            let temporary = tempfile::tempdir_in(parent)?;
            let link = temporary.path().join("identity");
            symlink(source, &link)?;
            fs::rename(link, destination)?;
        }
        (None, Some(git)) => {
            let name = git_identity(&git, "name").await?;
            let email = git_identity(&git, "email").await?;
            if name.is_empty() || email.is_empty() {
                match fs::remove_file(destination) {
                    Ok(()) => {}
                    Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
                    Err(e) => return Err(e.into()),
                }
                return Ok(());
            }
            let parent = private_parent(&destination)?;
            let escape = |s: &str| serde_json::to_string(s).map(|s| s.replace('\u{7f}', "\\u007f"));
            let text = format!(
                "[user]\nname = {}\nemail = {}\n",
                escape(&name)?,
                escape(&email)?
            );
            let mut temporary = tempfile::NamedTempFile::new_in(parent)?;
            temporary.write_all(text.as_bytes())?;
            temporary.as_file().sync_all()?;
            temporary.persist(destination)?;
        }
        _ => return Err("exactly one identity mode required".into()),
    }
    Ok(())
}
#[tokio::main(flavor = "current_thread")]
async fn main() -> std::process::ExitCode {
    match run().await {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(_) => {
            eprintln!("Unable to install the private Jujutsu identity.");
            std::process::ExitCode::FAILURE
        }
    }
}
