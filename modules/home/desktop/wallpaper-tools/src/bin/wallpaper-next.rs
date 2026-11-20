use rand::seq::SliceRandom;
use serde_json::Value;
use std::{
    error::Error,
    fs,
    io::Write,
    os::unix::{
        ffi::{OsStrExt, OsStringExt},
        fs::{DirBuilderExt, PermissionsExt},
    },
    path::PathBuf,
    time::{Duration, Instant},
};
type Result<T> = std::result::Result<T, Box<dyn Error>>;
async fn run() -> Result<()> {
    let policy: Value = serde_json::from_slice(&fs::read(
        std::env::args_os().nth(1).ok_or("policy required")?,
    )?)?;
    let text = |key: &str| -> Result<&str> {
        policy[key]
            .as_str()
            .ok_or_else(|| format!("missing {key}").into())
    };
    let source = PathBuf::from(text("directory")?);
    let state = PathBuf::from(text("state")?);
    if !source.is_dir() {
        return Ok(());
    }
    let deadline = Instant::now() + Duration::from_secs(120);
    let command = |mut c: tokio::process::Command, input| async move {
        nix_conf_process::run(
            &mut c,
            input,
            deadline.saturating_duration_since(Instant::now()),
        )
        .await
    };
    let mut paths = Vec::new();
    for entry in fs::read_dir(source)? {
        let entry = entry?;
        if !entry.file_type()?.is_file() {
            continue;
        }
        let path = entry.path();
        if path.extension().and_then(|s| s.to_str()).is_some_and(|s| {
            [
                "avif", "bmp", "gif", "jpeg", "jpg", "jxl", "png", "tif", "tiff", "webp",
            ]
            .contains(&s.to_ascii_lowercase().as_str())
        }) {
            paths.extend_from_slice(path.as_os_str().as_bytes());
            paths.push(0);
        }
    }
    let mut filter = tokio::process::Command::new(text("policyCommand")?);
    filter.args(["filter", "--null"]);
    let output = command(filter, Some(paths.as_slice())).await?;
    if !output.status.success() {
        return Err("wallpaper policy rejected preferences".into());
    }
    let mut paths: Vec<PathBuf> = output
        .stdout
        .split(|b| *b == 0)
        .filter(|s| !s.is_empty())
        .map(|s| PathBuf::from(std::ffi::OsString::from_vec(s.to_vec())))
        .collect();
    paths.shuffle(&mut rand::thread_rng());
    let number = |key: &str| -> Result<u128> {
        policy[key]
            .as_u64()
            .map(u128::from)
            .ok_or_else(|| format!("invalid {key}").into())
    };
    let (min_w, min_h, min_ratio, max_ratio) = (
        number("width")?,
        number("height")?,
        number("minAspectRatioScaled")?,
        number("maxAspectRatioScaled")?,
    );
    if min_w == 0 || min_h == 0 {
        return Err("wallpaper dimensions must be positive".into());
    }
    let mut selected = None;
    for path in paths {
        let mut identify = tokio::process::Command::new("magick");
        identify
            .args([
                "identify",
                "-ping",
                "-format",
                "%w %h %[orientation]\n",
                "--",
            ])
            .arg(&path);
        let output = command(identify, None).await?;
        if !output.status.success() {
            continue;
        }
        let line = String::from_utf8(output.stdout)?;
        let parts: Vec<_> = line.trim_end_matches('\n').split(' ').collect();
        if parts.len() != 3 || !parts[2].bytes().all(|b| b.is_ascii_alphabetic()) {
            continue;
        }
        let (Ok(mut w), Ok(mut h)) = (parts[0].parse::<u64>(), parts[1].parse::<u64>()) else {
            continue;
        };
        if ["LeftTop", "RightTop", "RightBottom", "LeftBottom"].contains(&parts[2]) {
            std::mem::swap(&mut w, &mut h);
        }
        let (w, h) = (u128::from(w), u128::from(h));
        if w >= min_w && h >= min_h && w * 1000 >= h * min_ratio && w * 1000 <= h * max_ratio {
            selected = Some(path);
            break;
        }
    }
    let mut display = tokio::process::Command::new("awww");
    display.arg("img");
    if !text("outputs")?.is_empty() {
        display.args(["--outputs", text("outputs")?]);
    }
    if let Some(path) = &selected {
        display
            .args([
                "--resize",
                "crop",
                "--filter",
                "Lanczos3",
                "--transition-type",
                text("transition")?,
                "--transition-duration",
                text("transitionDuration")?,
                "--transition-fps",
                text("transitionFps")?,
            ])
            .arg(path);
    } else {
        display.args(["--transition-type", "none", "0x000000"]);
    }
    if !command(display, None).await?.status.success() {
        return Err("wallpaper display failed".into());
    }
    if let Some(path) = selected {
        fs::DirBuilder::new()
            .recursive(true)
            .mode(0o700)
            .create(&state)?;
        fs::set_permissions(&state, fs::Permissions::from_mode(0o700))?;
        let mut current = tempfile::NamedTempFile::new_in(&state)?;
        current.write_all(path.as_os_str().as_bytes())?;
        writeln!(current)?;
        current.persist(state.join("current"))?;
    } else {
        match fs::remove_file(state.join("current")) {
            Ok(()) => (),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => (),
            Err(e) => return Err(e.into()),
        }
    }
    Ok(())
}
#[tokio::main(flavor = "current_thread")]
async fn main() -> std::process::ExitCode {
    match run().await {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("wallpaper rotation: {e}");
            std::process::ExitCode::FAILURE
        }
    }
}
