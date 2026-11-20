//! Refresh unpacked extensions outside the browser's startup path.
use fs2::FileExt;
use std::{
    error::Error,
    fs::{self, OpenOptions},
    path::{Component, Path},
    process::ExitCode,
    time::Duration,
};
use tokio::process::Command;
type Result<T> = std::result::Result<T, Box<dyn Error>>;

async fn run(binary: &str, args: &[&str]) -> Result<Vec<u8>> {
    let output = nix_conf_process::run(
        Command::new(binary).args(args),
        None,
        Duration::from_secs(15),
    )
    .await?;
    if !output.status.success() {
        return Err(format!(
            "{binary} failed: {}",
            String::from_utf8_lossy(&output.stderr)
        )
        .into());
    }
    Ok(output.stdout)
}
fn text(path: &Path) -> Result<&str> {
    path.to_str().ok_or_else(|| "non-UTF8 path".into())
}
async fn refresh(root: &Path, id: &str, url: &str, curl: &str, unzip: &str) -> Result<()> {
    let stage = tempfile::Builder::new()
        .prefix(".extension-")
        .tempdir_in(root)?;
    let crx = stage.path().join("extension.crx");
    let zip = stage.path().join("extension.zip");
    let unpacked = stage.path().join("unpacked");
    let request = format!(
        "{url}?response=redirect&acceptformat=crx2,crx3&prodversion=9999.0.0.0&x=id%3D{id}%26installsource%3Dondemand%26uc"
    );
    run(
        curl,
        &[
            "--fail",
            "--location",
            "--retry",
            "0",
            "--connect-timeout",
            "3",
            "--max-time",
            "8",
            "--max-filesize",
            "67108864",
            "--proto",
            "=https",
            "--proto-redir",
            "=https",
            "--silent",
            "--show-error",
            "--output",
            text(&crx)?,
            "--url",
            &request,
        ],
    )
    .await?;
    helium_crx_to_zip::convert(&crx, &zip)?;
    // Reject paths and symlink entries before extraction, including links used
    // as parents of later entries. unzip's own traversal protection also applies.
    let names = run(unzip, &["-Z1", text(&zip)?]).await?;
    for name in std::str::from_utf8(&names)?.lines() {
        if name.is_empty()
            || name.contains('\\')
            || name.chars().any(char::is_control)
            || Path::new(name)
                .components()
                .any(|c| !matches!(c, Component::Normal(_)))
        {
            return Err("unsafe archive path".into());
        }
    }
    let listing = run(unzip, &["-Z", "-l", text(&zip)?]).await?;
    if std::str::from_utf8(&listing)?
        .lines()
        .any(|line| line.starts_with('l'))
    {
        return Err("archive symlink rejected".into());
    }
    run(unzip, &["-q", text(&zip)?, "-d", text(&unpacked)?]).await?;
    if !unpacked.join("manifest.json").is_file() {
        return Err("missing extension manifest".into());
    }
    // Complete staging before moving the old directory; retain it until commit.
    let current = root.join(id);
    let backup = stage.path().join("previous");
    let had_current = current.symlink_metadata().is_ok();
    if had_current {
        fs::rename(&current, &backup)?;
    }
    if let Err(error) = fs::rename(&unpacked, &current) {
        if had_current && let Err(rollback) = fs::rename(&backup, &current) {
            let retained = stage.keep();
            return Err(format!("replacement failed: {error}; rollback failed: {rollback}; prior version retained in {}", retained.display()).into());
        }
        return Err(error.into());
    }
    Ok(())
}
async fn execute() -> Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let [mode, root, ids, url, curl, unzip] = args.as_slice() else {
        return Err("usage: helium-extension-update list|update ROOT IDS URL CURL UNZIP".into());
    };
    if args.iter().any(|s| s.len() > 16384 || s.contains('\0'))
        || !Path::new(root).is_absolute()
        || root.contains(',')
        || root.chars().any(char::is_control)
    {
        return Err("invalid extension arguments".into());
    }
    if !url.starts_with("https://")
        || url.len() > 4096
        || url[8..].is_empty()
        || url
            .chars()
            .any(|c| c.is_control() || c.is_whitespace() || matches!(c, '?' | '#'))
    {
        return Err("invalid update URL".into());
    }
    if !matches!(mode.as_str(), "list" | "update") {
        return Err("invalid mode".into());
    }
    let bytes = fs::read(ids)?;
    if bytes.len() > 65536 {
        return Err("too many extension IDs".into());
    }
    let ids: Vec<_> = std::str::from_utf8(&bytes)?
        .lines()
        .filter(|s| !s.is_empty())
        .collect();
    if ids.len() > 512
        || ids
            .iter()
            .any(|id| id.len() != 32 || !id.bytes().all(|b| (b'a'..=b'p').contains(&b)))
    {
        return Err("invalid extension IDs".into());
    }
    let root = Path::new(root);
    fs::create_dir_all(root)?;
    if mode == "list" {
        let paths: Vec<_> = ids
            .iter()
            .map(|id| root.join(id))
            .filter(|p| p.is_dir())
            .collect();
        if !paths.is_empty() {
            let flag = format!(
                "--load-extension={}",
                paths
                    .iter()
                    .map(|p| p.to_string_lossy())
                    .collect::<Vec<_>>()
                    .join(",")
            );
            if flag.len() > 65536 {
                return Err("extension flag exceeds argument bound".into());
            }
            println!("{flag}");
        }
        return Ok(());
    }
    // Keep the lock inode stable: unlinking it would permit two owners. The OS
    // releases the advisory lock on every exit, including cancellation.
    let lock = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(root.join(".update.lock"))?;
    if lock.try_lock_exclusive().is_err() {
        return Ok(());
    }
    for id in ids {
        if let Err(error) = refresh(root, id, url, curl, unzip).await {
            eprintln!("{id}: {error}");
        }
    }
    Ok(())
}
async fn guarded() -> Result<u8> {
    use tokio::signal::unix::{SignalKind, signal};
    let mut term = signal(SignalKind::terminate())?;
    let mut interrupt = signal(SignalKind::interrupt())?;
    let mut hup = signal(SignalKind::hangup())?;
    tokio::select! {result=execute()=>result.map(|()|0),_=term.recv()=>Ok(143),_=interrupt.recv()=>Ok(130),_=hup.recv()=>Ok(129)}
}
#[tokio::main(flavor = "current_thread")]
async fn main() -> ExitCode {
    match guarded().await {
        Ok(code) => ExitCode::from(code),
        Err(e) => {
            eprintln!("helium-extension-update: {e}");
            ExitCode::FAILURE
        }
    }
}
