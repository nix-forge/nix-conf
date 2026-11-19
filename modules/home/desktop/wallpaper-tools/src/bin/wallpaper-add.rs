//! Admit local image files into the private wallpaper directory atomically.
use std::{
    env, fs,
    io::{self, Write},
    os::unix::fs::{MetadataExt, PermissionsExt},
    path::Path,
    process::ExitCode,
    time::Duration,
};
type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
async fn run() -> Result<u8> {
    let args: Vec<_> = env::args_os().skip(1).collect();
    if args.len() != 2 || !Path::new(&args[1]).is_file() {
        eprintln!("Usage: desktop-wallpaper-add /path/to/image");
        return Ok(64);
    }
    let source = Path::new(&args[1]);
    let root = Path::new(&args[0]);
    let output = nix_conf_process::run(
        tokio::process::Command::new("file")
            .args(["--brief", "--mime-type", "--"])
            .arg(source),
        None,
        Duration::from_secs(10),
    )
    .await?;
    if !output.status.success() {
        return Err("image type detection failed".into());
    }
    let mime = String::from_utf8(output.stdout)?;
    let mime = mime.trim_end_matches('\n');
    if ![
        "image/avif",
        "image/bmp",
        "image/gif",
        "image/jpeg",
        "image/jxl",
        "image/png",
        "image/tiff",
        "image/webp",
    ]
    .contains(&mime)
    {
        eprintln!("Refusing non-image input (detected {mime}).");
        return Ok(65);
    }
    fs::create_dir_all(root)?;
    fs::set_permissions(root, fs::Permissions::from_mode(0o700))?;
    let destination = root.join(source.file_name().ok_or("input filename missing")?);
    let mut input = fs::File::open(source)?;
    let identity = input.metadata()?;
    if fs::metadata(&destination)
        .is_ok_and(|m| m.dev() == identity.dev() && m.ino() == identity.ino())
    {
        return Err("source and destination are the same file".into());
    }
    let mut temporary = tempfile::NamedTempFile::new_in(root)?;
    io::copy(&mut input, &mut temporary)?;
    temporary.flush()?;
    temporary.as_file().sync_all()?;
    temporary.persist(destination)?;
    Ok(0)
}
async fn guarded() -> Result<u8> {
    use tokio::signal::unix::{SignalKind, signal};
    let mut term = signal(SignalKind::terminate())?;
    let mut interrupt = signal(SignalKind::interrupt())?;
    let mut hup = signal(SignalKind::hangup())?;
    tokio::select! {result=run()=>result,_=term.recv()=>Ok(143),_=interrupt.recv()=>Ok(130),_=hup.recv()=>Ok(129)}
}
#[tokio::main(flavor = "current_thread")]
async fn main() -> ExitCode {
    match guarded().await {
        Ok(code) => ExitCode::from(code),
        Err(e) => {
            eprintln!("desktop-wallpaper-add: {e}");
            ExitCode::FAILURE
        }
    }
}
