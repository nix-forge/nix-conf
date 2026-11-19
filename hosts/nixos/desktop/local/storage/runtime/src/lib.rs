//! Host storage maintenance. Private diagnostics never cross the command boundary.
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    fs::{self, File, OpenOptions},
    io::{Read, Write},
    os::unix::fs::{OpenOptionsExt, PermissionsExt},
    path::{Path, PathBuf},
    process::Output,
    time::{Duration, SystemTime, UNIX_EPOCH},
};
pub type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
pub const LEGACY_DATA_MOUNT: &str = "/srv/data";
#[derive(Debug)]
pub struct Usage(pub String);
impl std::fmt::Display for Usage {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}
impl std::error::Error for Usage {}
pub fn usage<T>(message: &str) -> Result<T> {
    Err(Box::new(Usage(message.into())))
}
pub fn usage_error(message: &str) -> Box<dyn std::error::Error> {
    Box::new(Usage(message.into()))
}
pub fn fail<T>(message: &str) -> Result<T> {
    Err(message.into())
}
pub fn s(v: &Value) -> &str {
    v.as_str().unwrap_or("")
}
pub fn policy_path<'a>(policy: &'a Value, field: &str, fallback: &'a str) -> Result<&'a str> {
    let fields = policy
        .as_object()
        .ok_or("Storage policy must be an object")?;
    match fields.get(field) {
        None => Ok(fallback),
        Some(value) => value
            .as_str()
            .filter(|path| Path::new(path).is_absolute())
            .ok_or_else(|| format!("Storage policy field {field} must be an absolute path").into()),
    }
}
pub fn n(v: &Value) -> u64 {
    v.as_u64().unwrap_or(0)
}
pub fn list(v: &Value) -> Vec<String> {
    v.as_array()
        .map(|a| a.iter().map(|x| s(x).to_owned()).collect())
        .unwrap_or_default()
}
pub fn now() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.)
}
pub fn read(path: impl AsRef<Path>) -> Result<Value> {
    Ok(serde_json::from_slice(&fs::read(path)?)?)
}
pub fn optional(path: impl AsRef<Path>) -> Result<Value> {
    match read(path) {
        Ok(v) if v.is_object() => Ok(v),
        Err(e)
            if e.downcast_ref::<std::io::Error>()
                .is_some_and(|e| e.kind() == std::io::ErrorKind::NotFound) =>
        {
            Ok(json!({}))
        }
        Ok(_) => fail("State is not an object"),
        Err(e) => Err(e),
    }
}
pub fn save(path: impl AsRef<Path>, value: &Value, mode: u32) -> Result<()> {
    let path = path.as_ref();
    let parent = path.parent().ok_or("Missing parent")?;
    fs::create_dir_all(parent)?;
    let mut tmp = tempfile::NamedTempFile::new_in(parent)?;
    tmp.as_file()
        .set_permissions(fs::Permissions::from_mode(mode))?;
    serde_json::to_writer(&mut tmp, value)?;
    tmp.write_all(b"\n")?;
    tmp.as_file().sync_all()?;
    tmp.persist(path)?;
    Ok(())
}
pub fn hash(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}
/// Preserve the sorted, ASCII JSON encoding used by existing reviewed plans
/// and delivery receipts, so the migration does not invalidate their hashes.
pub fn receipt_hash(value: &Value) -> Result<String> {
    fn encode(value: &Value) -> Result<String> {
        Ok(match value {
            Value::Array(values) => format!(
                "[{}]",
                values
                    .iter()
                    .map(encode)
                    .collect::<Result<Vec<_>>>()?
                    .join(", ")
            ),
            Value::Object(values) => {
                let mut keys = values.keys().collect::<Vec<_>>();
                keys.sort();
                let fields = keys
                    .into_iter()
                    .map(|key| {
                        Ok(format!(
                            "{}: {}",
                            encode(&json!(key))?,
                            encode(&values[key])?
                        ))
                    })
                    .collect::<Result<Vec<String>>>()?;
                format!("{{{}}}", fields.join(", "))
            }
            Value::String(_) => {
                let text = serde_json::to_string(value)?;
                let mut escaped = String::new();
                for c in text.chars() {
                    if c.is_ascii() {
                        escaped.push(c);
                    } else {
                        for unit in c.encode_utf16(&mut [0; 2]) {
                            escaped.push_str(&format!("\\u{unit:04x}"));
                        }
                    }
                }
                escaped
            }
            _ => value.to_string(),
        })
    }
    Ok(hash(encode(value)?.as_bytes()))
}
pub fn fingerprint(path: &Path) -> Result<Value> {
    fs::set_permissions(path, fs::Permissions::from_mode(0o600))?;
    let mut f = File::open(path)?;
    let mut h = Sha256::new();
    let mut buf = [0; 65536];
    loop {
        let got = f.read(&mut buf)?;
        if got == 0 {
            break;
        }
        h.update(&buf[..got]);
    }
    Ok(
        json!({"file": path.file_name().ok_or("Missing name")?.to_string_lossy(), "bytes": f.metadata()?.len(), "sha256": format!("{:x}",h.finalize())}),
    )
}
pub fn state(p: &Value, name: &str) -> PathBuf {
    Path::new(s(&p["stateDirectory"])).join(name)
}
pub fn lock(path: &str, nonblocking: bool) -> Result<File> {
    let file = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .open(path)?;
    if nonblocking {
        fs2::FileExt::try_lock_exclusive(&file)?;
    } else {
        fs2::FileExt::lock_exclusive(&file)?;
    }
    Ok(file)
}
pub fn existing_lock(path: &str, nonblocking: bool) -> Result<File> {
    let file = OpenOptions::new().read(true).write(true).open(path)?;
    if nonblocking {
        fs2::FileExt::try_lock_exclusive(&file)?;
    } else {
        fs2::FileExt::lock_exclusive(&file)?;
    }
    Ok(file)
}
pub fn root() -> Result<()> {
    if !rustix::process::geteuid().is_root() {
        return usage("This operation requires root");
    }
    Ok(())
}
pub fn args() -> Vec<String> {
    std::env::args().skip(1).collect()
}
pub fn option(a: &[String], name: &str) -> Option<String> {
    a.windows(2).find(|w| w[0] == name).map(|w| w[1].clone())
}
pub fn entry(f: impl FnOnce() -> Result<i32>) {
    match f() {
        Ok(code) => std::process::exit(code),
        Err(e) => {
            eprintln!("Storage operation refused: {e}");
            std::process::exit(if e.is::<Usage>() { 2 } else { 1 });
        }
    }
}
/// Command output is private; callers publish only explicit labels. Signals are
/// handled while the owner still has the child and its process group.
pub fn output(a: &[String], timeout: u64, input: Option<&[u8]>) -> Result<Output> {
    output_capture(a, timeout, input, None, 0)
}
pub fn output_tail(a: &[String], timeout: u64, limit: usize) -> Result<Output> {
    output_capture(a, timeout, None, Some(limit), 0)
}
// Tokio's replacement registration requires unsafe code. This compatibility
// API owns an OwnedFd whose descriptor cannot change during registration.
#[allow(
    deprecated,
    reason = "safe owned-descriptor API retained until its replacement is available"
)]
pub fn output_capture(
    a: &[String],
    timeout: u64,
    input: Option<&[u8]>,
    limit: Option<usize>,
    grace: u64,
) -> Result<Output> {
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?;
    Ok(rt.block_on(async {
        use tokio::{
            io::{AsyncReadExt, AsyncWriteExt},
            signal::unix::{SignalKind, signal},
        };
        let mut term = signal(SignalKind::terminate())?;
        let mut int = signal(SignalKind::interrupt())?;
        let program = a
            .first()
            .ok_or_else(|| std::io::Error::other("Empty command"))?;
        let mut command = tokio::process::Command::new(program);
        command
            .args(&a[1..])
            .process_group(0)
            .kill_on_drop(true)
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped());
        let mut child = command.spawn()?;
        let pid = child
            .id()
            .and_then(|p| rustix::process::Pid::from_raw(p as i32))
            .ok_or_else(|| std::io::Error::other("Child PID missing"))?;
        let mut stdin = child
            .stdin
            .take()
            .ok_or_else(|| std::io::Error::other("stdin"))?;
        let mut stdout = child
            .stdout
            .take()
            .ok_or_else(|| std::io::Error::other("stdout"))?;
        let mut stderr = child
            .stderr
            .take()
            .ok_or_else(|| std::io::Error::other("stderr"))?;
        let fd = rustix::process::pidfd_open(pid, rustix::process::PidfdFlags::empty())?;
        let observer = tokio::io::unix::AsyncFd::new(fd)?;
        let mut out = Vec::new();
        let mut err = Vec::new();
        async fn capture<R: tokio::io::AsyncRead + Unpin>(
            source: &mut R,
            buffer: &mut Vec<u8>,
            limit: Option<usize>,
        ) -> std::io::Result<()> {
            let mut block = [0; 8192];
            loop {
                let count = source.read(&mut block).await?;
                if count == 0 {
                    return Ok(());
                }
                buffer.extend_from_slice(&block[..count]);
                if let Some(limit) = limit
                    && buffer.len() > limit
                {
                    buffer.drain(..buffer.len() - limit);
                }
            }
        }
        let result = {
            let work = async {
                tokio::try_join!(
                    async {
                        if let Some(bytes) = input {
                            stdin.write_all(bytes).await?;
                        }
                        drop(stdin);
                        Ok::<_, std::io::Error>(())
                    },
                    capture(&mut stdout, &mut out, limit),
                    capture(&mut stderr, &mut err, limit),
                    async {
                        let _ready = observer.readable().await?;
                        Ok::<_, std::io::Error>(())
                    }
                )
                .map(|_| ())
            };
            tokio::select! {
                result = tokio::time::timeout(Duration::from_secs(timeout), work) => match result {
                    Ok(value) => value,
                    Err(_) => Err(std::io::Error::other("Command deadline exceeded")),
                },
                _ = term.recv() => Err(std::io::Error::other("Operation interrupted")),
                _ = int.recv() => Err(std::io::Error::other("Operation interrupted")),
            }
        };
        // The unreaped leader reserves the group ID while descendants are
        // inspected and killed. pidfd readiness does not consume wait status.
        let unfinished = fs::read_dir("/proc")
            .map(|entries| {
                entries.filter_map(|entry| entry.ok()).any(|entry| {
                    let id = entry.file_name().to_string_lossy().parse::<i32>().ok();
                    if id.is_none() || id == Some(pid.as_raw_nonzero().get()) {
                        return false;
                    }
                    fs::read_to_string(entry.path().join("stat"))
                        .ok()
                        .and_then(|text| {
                            text.rsplit_once(')').map(|(_, fields)| {
                                fields
                                    .split_whitespace()
                                    .nth(2)
                                    .and_then(|value| value.parse::<i32>().ok())
                                    == Some(pid.as_raw_nonzero().get())
                            })
                        })
                        .unwrap_or(false)
                })
            })
            .unwrap_or(true);
        if result.is_err() && grace > 0 {
            let _signal_result =
                rustix::process::kill_process_group(pid, rustix::process::Signal::INT);
            let _grace_result = tokio::time::timeout(Duration::from_secs(grace), async {
                tokio::try_join!(
                    capture(&mut stdout, &mut out, limit),
                    capture(&mut stderr, &mut err, limit),
                    observer.readable()
                )
            })
            .await;
        }
        let _signal_result =
            rustix::process::kill_process_group(pid, rustix::process::Signal::KILL);
        let status = tokio::time::timeout(Duration::from_secs(5), child.wait())
            .await
            .map_err(|_| std::io::Error::other("Child reap deadline exceeded"))??;
        result?;
        if unfinished {
            return Err(std::io::Error::other(
                "Command left unfinished child processes",
            ));
        }
        Ok::<_, std::io::Error>(Output {
            status,
            stdout: out,
            stderr: err,
        })
    })?)
}

pub fn run(a: &[String]) -> Result<String> {
    let o = output(a, 86400, None)?;
    if !o.status.success() {
        return fail("Utility failed; inspect the owning service privately");
    }
    Ok(String::from_utf8(o.stdout)?)
}
pub fn cmd(a: &[&str]) -> Result<String> {
    run(&a.iter().map(|v| (*v).to_string()).collect::<Vec<_>>())
}
pub mod backup;
