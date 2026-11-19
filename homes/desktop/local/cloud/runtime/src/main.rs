//! Private encrypted rclone state; child diagnostics never cross this boundary.
use serde_json::Value;
use std::{
    env,
    fs::{self, OpenOptions},
    io::{Read, Write},
    os::unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt},
    path::{Path, PathBuf},
    process::Stdio,
    time::{Duration, Instant},
};
use tokio::{
    io::{AsyncBufReadExt, BufReader},
    process::Command,
};
type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
struct Policy(Value);
impl Policy {
    fn get(&self, key: &str) -> Result<&str> {
        self.0[key]
            .as_str()
            .ok_or_else(|| "Invalid Drive policy".into())
    }
    fn path(&self, key: &str) -> Result<PathBuf> {
        Ok(PathBuf::from(self.get(key)?))
    }
    fn config(&self) -> Result<PathBuf> {
        Ok(self.path("stateDirectory")?.join("rclone.conf"))
    }
    fn rclone(&self, config: &Path) -> Result<Command> {
        let mut command = Command::new(self.get("rclone")?);
        let password_command = shell_words::join([self.get("cat")?, self.get("passwordFile")?]);
        command.args(["--config"]).arg(config).args([
            "--password-command",
            &password_command,
            "--ask-password=false",
        ]);
        Ok(command)
    }
    async fn systemctl(&self, action: &str) -> Result<i32> {
        let status = Command::new(self.get("systemctl")?)
            .args(["--user", action, "google-drive.service"])
            .status()
            .await?;
        Ok(status.code().unwrap_or(1))
    }
}
fn private_dir(path: &Path) -> Result<()> {
    for ancestor in path.ancestors() {
        match fs::symlink_metadata(ancestor) {
            Ok(info) if info.file_type().is_symlink() => {
                return Err("Symlink in managed directory".into());
            }
            Ok(_) => (),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => (),
            Err(e) => return Err(e.into()),
        }
    }
    fs::create_dir_all(path)?;
    let info = fs::metadata(path)?;
    if !info.is_dir() || info.uid() != rustix::process::getuid().as_raw() {
        return Err("Foreign managed directory".into());
    }
    fs::set_permissions(path, fs::Permissions::from_mode(0o700))?;
    Ok(())
}
fn private_file(path: &Path) -> Result<()> {
    let info = fs::symlink_metadata(path)?;
    if !info.is_file()
        || info.uid() != rustix::process::getuid().as_raw()
        || info.mode() & 0o077 != 0
    {
        return Err("Unsafe private state".into());
    }
    Ok(())
}
fn encrypted(path: &Path) -> Result<()> {
    private_file(path)?;
    let mut bytes = vec![];
    fs::File::open(path)?.take(256).read_to_end(&mut bytes)?;
    if !bytes.windows(18).any(|v| v == b"RCLONE_ENCRYPT_V0:") {
        return Err("Unencrypted configuration".into());
    }
    Ok(())
}
fn mounted(path: &Path) -> Result<bool> {
    // mountinfo, unlike parent device comparisons, also detects bind mounts.
    let absolute = fs::canonicalize(path).unwrap_or_else(|_| path.to_owned());
    let encoded = absolute
        .to_str()
        .ok_or("Invalid mount path")?
        .replace('\\', "\\134")
        .replace(' ', "\\040")
        .replace('\t', "\\011")
        .replace('\n', "\\012");
    Ok(fs::read_to_string("/proc/self/mountinfo")?
        .lines()
        .any(|line| line.split_whitespace().nth(4) == Some(encoded.as_str())))
}
fn initialize(policy: &Policy) -> Result<()> {
    private_dir(&policy.path("stateDirectory")?)?;
    let mount = policy.path("mountDirectory")?;
    if !mounted(&mount)? {
        private_dir(&mount)?;
    }
    Ok(())
}
fn client_configuration(path: &Path) -> Result<String> {
    private_file(path)?;
    let mut bytes = vec![];
    fs::File::open(path)?.take(65537).read_to_end(&mut bytes)?;
    if bytes.len() > 65536 {
        return Err("Oversized OAuth client".into());
    }
    let document: Value = serde_json::from_slice(&bytes)?;
    let client = &document["installed"];
    let id = client["client_id"].as_str().ok_or("Missing client ID")?;
    let secret = client["client_secret"]
        .as_str()
        .ok_or("Missing client secret")?;
    if [id, secret]
        .iter()
        .any(|v| v.is_empty() || v.contains(['\r', '\n', '\0']))
        || client["auth_uri"] != "https://accounts.google.com/o/oauth2/auth"
        || client["token_uri"] != "https://oauth2.googleapis.com/token"
    {
        return Err("Invalid Desktop OAuth client".into());
    }
    Ok(format!(
        "[google-drive]\ntype = drive\nclient_id = {id}\nclient_secret = {secret}\nscope = drive\nuse_trash = true\nskip_shortcuts = true\nskip_gdocs = true\n\n"
    ))
}
async fn checked(command: &mut Command) -> Result<()> {
    if !command
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .await?
        .success()
    {
        return Err("Drive operation failed".into());
    }
    Ok(())
}
async fn reconnect(policy: &Policy) -> Result<()> {
    if policy.systemctl("stop").await? != 0 {
        return Err("Drive stop failed".into());
    }
    let config = policy.config()?;
    encrypted(&config)?;
    checked(
        policy
            .rclone(&config)?
            .args(["config", "reconnect", "google-drive:"]),
    )
    .await?;
    encrypted(&config)?;
    let _reset_result = policy.systemctl("reset-failed").await;
    if policy.systemctl("start").await? != 0 {
        return Err("Drive start failed".into());
    }
    println!("Google Drive is connected. Open the Google Drive bookmark in Files.");
    Ok(())
}
async fn setup(policy: &Policy) -> Result<()> {
    initialize(policy)?;
    private_file(&policy.path("passwordFile")?)?;
    let destination = policy.config()?;
    if fs::symlink_metadata(&destination).is_ok() {
        return Err("Configuration already exists; reconnect instead".into());
    }
    let content = client_configuration(&policy.path("clientFile")?)?;
    let temporary = tempfile::Builder::new()
        .prefix("google-drive-")
        .tempdir_in(policy.path("runtimeDirectory")?)?;
    let seed = temporary.path().join("rclone.conf");
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&seed)?;
    file.write_all(content.as_bytes())?;
    drop(file);
    checked(policy.rclone(&seed)?.args(["config", "encryption", "set"])).await?;
    encrypted(&seed)?;
    let mut output = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .custom_flags(rustix::fs::OFlags::NOFOLLOW.bits() as i32)
        .open(destination)?;
    output.write_all(&fs::read(seed)?)?;
    output.sync_all()?;
    drop(temporary);
    reconnect(policy).await
}
async fn notify(policy: &Policy, body: &str) {
    if let Ok(program) = policy.get("notify") {
        let _cleanup_result = nix_conf_process::run(
            Command::new(program).args(["--urgency=critical", "Google Drive", body]),
            None,
            Duration::from_secs(10),
        )
        .await;
    }
}
async fn mount(policy: &Policy) -> Result<i32> {
    initialize(policy)?;
    let config = policy.config()?;
    encrypted(&config)?;
    private_file(&policy.path("passwordFile")?)?;
    let mount = policy.path("mountDirectory")?;
    if mounted(&mount)? || fs::read_dir(&mount)?.next().is_some() {
        return Err("Mount must be empty and unmounted".into());
    }
    let cache = policy.path("stateDirectory")?.join("vfs-cache");
    private_dir(&cache)?;
    let mut command = policy.rclone(&config)?;
    command
        .args(["mount", "google-drive:"])
        .arg(&mount)
        .arg("--cache-dir")
        .arg(cache)
        .args([
            "--vfs-cache-mode=full",
            "--vfs-cache-max-size=5Gi",
            "--vfs-cache-min-free-space=10Gi",
            "--buffer-size=8Mi",
            "--transfers=2",
            "--umask=077",
            "--drive-use-trash=true",
            "--drive-skip-shortcuts=true",
            "--drive-skip-gdocs=true",
            "--log-level=ERROR",
        ])
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .kill_on_drop(true);
    let mut child = command.spawn()?;
    let stderr = child.stderr.take().ok_or("Missing error stream")?;
    let mut reader = BufReader::new(stderr);
    let mut buffer = Vec::new();
    let mut last_notice = None;
    let mut term = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())?;
    let mut interrupt = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::interrupt())?;
    let mut closed = false;
    loop {
        buffer.clear();
        tokio::select! {
            status=child.wait(), if closed=>return Ok(status?.code().unwrap_or(1)),
            _=term.recv()=> { if let Some(pid)=child.id().and_then(|p|rustix::process::Pid::from_raw(p as i32)) {let _signal_result = rustix::process::kill_process(pid,rustix::process::Signal::TERM);} },
            _=interrupt.recv()=> { if let Some(pid)=child.id().and_then(|p|rustix::process::Pid::from_raw(p as i32)) {let _signal_result = rustix::process::kill_process(pid,rustix::process::Signal::TERM);} },
            read=reader.read_until(b'\n',&mut buffer), if !closed=> {
                if read?==0 {closed=true;continue;}
                println!("Google Drive reported an error; cached uploads are retained.");
                if last_notice.is_none_or(|t:Instant|t.elapsed()>=Duration::from_secs(60)) {notify(policy,"A Drive operation failed. Keep the local cache until uploads finish.").await;last_notice=Some(Instant::now());}
            }
        }
    }
}
async fn run() -> Result<i32> {
    rustix::process::setrlimit(
        rustix::process::Resource::Core,
        rustix::process::Rlimit {
            current: Some(0),
            maximum: Some(0),
        },
    )?;
    rustix::process::umask(rustix::fs::Mode::from_raw_mode(0o077));
    let args: Vec<_> = env::args().skip(1).collect();
    if args.len() != 3 || args[0] != "--policy" {
        return Err("Expected --policy FILE ACTION".into());
    }
    let policy = Policy(serde_json::from_slice(&fs::read(&args[1])?)?);
    match args[2].as_str() {
        "init" => initialize(&policy)?,
        "setup" => setup(&policy).await?,
        "reconnect" => reconnect(&policy).await?,
        "mount" => return mount(&policy).await,
        "stopped" => {
            if env::var("SERVICE_RESULT").unwrap_or_else(|_| "success".into()) != "success" {
                notify(
                    &policy,
                    "The Drive mount stopped unexpectedly. Cached uploads remain on disk.",
                )
                .await;
            }
        }
        action @ ("start" | "stop" | "status") => return policy.systemctl(action).await,
        _ => return Err("Invalid Drive action".into()),
    }
    Ok(0)
}
#[tokio::main(flavor = "current_thread")]
async fn main() {
    let code = match run().await {
        Ok(code) => code,
        Err(_) => {
            eprintln!(
                "Google Drive setup failed. Check private credentials and encrypted state; no values were printed."
            );
            1
        }
    };
    std::process::exit(code);
}
