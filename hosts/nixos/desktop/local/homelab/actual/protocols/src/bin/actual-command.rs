use fs2::FileExt;
use std::{
    env,
    fs::{self, DirBuilder, OpenOptions},
    os::unix::{
        fs::{DirBuilderExt, OpenOptionsExt, PermissionsExt},
        process::CommandExt,
    },
    path::Path,
    process::Command,
    time::Duration,
};
type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
async fn actual() -> Result<()> {
    rustix::process::umask(rustix::fs::Mode::from_bits_truncate(0o077));
    let mut args = env::args_os().skip(1);
    let server = args.next().ok_or("Missing server origin")?;
    let identity = args.next().ok_or("Missing identity origin")?;
    let cli = args.next().ok_or("Missing CLI program")?;
    let mount = tokio::time::timeout(
        Duration::from_secs(10),
        tokio::process::Command::new("findmnt")
            .args(["-rn", "-o", "SOURCE", "--target", "/srv/actual"])
            .kill_on_drop(true)
            .output(),
    )
    .await??;
    if !mount.status.success()
        || mount.stdout.strip_suffix(b"\n").unwrap_or(&mount.stdout) != b"/dev/mapper/actual-vault"
    {
        return Err("Actual encrypted storage is unavailable".into());
    }
    let runtime = Path::new("/run/nix-seal/actual-cli");
    DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(runtime)?;
    fs::set_permissions(runtime, fs::Permissions::from_mode(0o700))?;
    let lock = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .open(runtime.join("login.lock"))?;
    let lock = tokio::task::spawn_blocking(move || {
        lock.lock_exclusive()?;
        Ok::<_, std::io::Error>(lock)
    })
    .await??;
    let token = runtime.join("session-token");
    // Preserve find -mmin +1380: completed minute age exceeds 1380.
    // Refresh under the same lock as login.
    let refresh = match fs::metadata(&token) {
        Ok(meta) => {
            meta.len() == 0
                || meta
                    .modified()?
                    .elapsed()
                    .is_ok_and(|age| age >= Duration::from_secs(1381 * 60))
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => true,
        Err(error) => return Err(error.into()),
    };
    if refresh {
        let paths = ["username", "password", "session-token"]
            .map(|name| runtime.join(name).to_string_lossy().into_owned());
        actual_protocols::login_with_origins(
            &paths,
            &server.to_string_lossy(),
            &identity.to_string_lossy(),
        )
        .await?;
    }
    FileExt::unlock(&lock)?;
    drop(lock);
    let error = Command::new(cli)
        .args(args)
        .env("ACTUAL_SERVER_URL", server)
        .env("ACTUAL_IDENTITY_URL", identity)
        .env("ACTUAL_SESSION_TOKEN_FILE", token)
        .env("ACTUAL_DATA_DIR", "/srv/actual/cli")
        .exec();
    eprintln!("Actual CLI execution failed");
    std::process::exit(if error.kind() == std::io::ErrorKind::NotFound {
        127
    } else {
        126
    });
}
async fn guarded() -> Result<u8> {
    use tokio::signal::unix::{SignalKind, signal};
    let mut term = signal(SignalKind::terminate())?;
    let mut interrupt = signal(SignalKind::interrupt())?;
    let mut hup = signal(SignalKind::hangup())?;
    tokio::select! {result=actual()=>result.map(|()|0),_=term.recv()=>Ok(143),_=interrupt.recv()=>Ok(130),_=hup.recv()=>Ok(129)}
}
fn main() {
    let runtime = match tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
    {
        Ok(runtime) => runtime,
        Err(_) => {
            eprintln!("Actual command failed");
            std::process::exit(1);
        }
    };
    let result = runtime.block_on(guarded());
    // A cancelled blocking flock waiter must not hold process shutdown open.
    runtime.shutdown_background();
    if let Err(error) = result {
        // Never print credentials, secret paths or environment values on failure.
        if error.to_string() == "Actual encrypted storage is unavailable" {
            eprintln!("{error}");
        } else {
            eprintln!("Actual command failed");
        }
        std::process::exit(1);
    }
    if let Ok(code) = result {
        std::process::exit(i32::from(code));
    }
}
