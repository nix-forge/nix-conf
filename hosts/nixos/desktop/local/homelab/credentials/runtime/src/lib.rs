mod inventory;
mod sealed;
mod setup;
mod vault;
use base64::{Engine, engine::general_purpose::STANDARD};
use serde_json::{Value, json};
use std::{
    collections::BTreeMap,
    io::{self, Read, Write},
    os::unix::fs::OpenOptionsExt,
    path::{Path, PathBuf},
    time::Duration,
};
use tokio::process::Command;
type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
fn fail<T>(message: &str) -> Result<T> {
    Err(io::Error::other(message).into())
}
fn string(v: &Value) -> &str {
    v.as_str().unwrap_or("")
}
fn array(v: &Value) -> &[Value] {
    v.as_array().map(Vec::as_slice).unwrap_or(&[])
}
fn read_json(p: &Path) -> Result<Value> {
    Ok(serde_json::from_slice(&std::fs::read(p)?)?)
}
fn domain() -> &'static str {
    string_domain()
}
fn string_domain() -> &'static str {
    static DOMAIN: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    DOMAIN.get_or_init(|| {
        serde_json::from_str::<Value>(include_str!(
            "../../../../../../../../hosts/shared/local/network.json"
        ))
        .ok()
        .map(|v| string(&v["homelabDomain"]).to_owned())
        .unwrap_or_default()
    })
}
async fn run(
    args: &[&str],
    input: Option<&[u8]>,
    env: &BTreeMap<String, String>,
) -> Result<String> {
    let mut c = Command::new(args[0]);
    c.args(&args[1..]).envs(env);
    // Each operation owns a single bounded deadline and process group.
    let out = nix_conf_process::run(&mut c, input, Duration::from_secs(180)).await?;
    if !out.status.success() {
        return fail("external operation failed; sensitive output suppressed");
    }
    Ok(String::from_utf8(out.stdout)?)
}
async fn command(args: &[&str], input: Option<&str>) -> Result<String> {
    run(args, input.map(str::as_bytes), &BTreeMap::new()).await
}
fn encode(v: &[u8]) -> String {
    STANDARD.encode(v)
}
fn decode(v: &str) -> Result<Vec<u8>> {
    Ok(STANDARD.decode(v)?)
}
fn quote(v: &str) -> String {
    shell_words::quote(v).into_owned()
}
#[derive(Default)]
struct Args {
    values: BTreeMap<String, Vec<String>>,
}
impl Args {
    fn parse(command: &str) -> Result<Self> {
        let flags = ["dry-run", "apply", "prompt", "seal-only", "help"];
        let allowed: &[&str] = match command {
            "homelab-to-bitwarden" | "freshrss-to-bitwarden" => &[
                "credential-via-host",
                "only",
                "apply",
                "dry-run",
                "receipt",
                "help",
            ],
            "miniflux-to-bitwarden" => &[
                "plan",
                "bootstrap-plan",
                "identity",
                "authorizer-key",
                "administrator-host",
                "credential-via-host",
                "seal-only",
                "repo-root",
                "prompt",
                "help",
            ],
            "identity-to-bitwarden" => &[
                "plan",
                "bootstrap-plan",
                "session-file",
                "identity",
                "authorizer-key",
                "administrator-host",
                "identity-url",
                "wardrobe-url",
                "realm",
                "repo-root",
                "help",
            ],
            _ => &[],
        };
        let mut r = Self::default();
        let mut it = std::env::args().skip(1);
        while let Some(k) = it.next() {
            let raw = if k == "-h" { "--help" } else { &k };
            let raw = raw.strip_prefix("--").ok_or("expected option")?;
            let (k, inline) = raw
                .split_once('=')
                .map_or((raw, None), |(k, v)| (k, Some(v)));
            if !allowed.contains(&k) {
                return fail("unknown option");
            }
            let v = if flags.contains(&k) {
                if inline.is_some() {
                    return fail("flag takes no value");
                }
                String::new()
            } else if let Some(v) = inline {
                v.to_owned()
            } else {
                it.next().ok_or("missing option value")?
            };
            if k != "only" && r.has(k) {
                return fail("duplicate option");
            }
            r.values.entry(k.into()).or_default().push(v);
        }
        if !r.has("help") {
            let required: &[&str] = match command {
                "miniflux-to-bitwarden" => &["plan", "identity"],
                "identity-to-bitwarden" => &[
                    "plan",
                    "bootstrap-plan",
                    "session-file",
                    "identity",
                    "authorizer-key",
                    "administrator-host",
                    "identity-url",
                    "wardrobe-url",
                ],
                _ => &[],
            };
            for k in required {
                r.required(k)?;
            }
        }
        Ok(r)
    }
    fn has(&self, k: &str) -> bool {
        self.values.contains_key(k)
    }
    fn get<'a>(&'a self, k: &str, default: &'a str) -> &'a str {
        self.values
            .get(k)
            .and_then(|v| v.first())
            .map(String::as_str)
            .unwrap_or(default)
    }
    fn required(&self, k: &str) -> Result<&str> {
        if !self.has(k) || self.get(k, "").is_empty() {
            fail("required option missing")
        } else {
            Ok(self.get(k, ""))
        }
    }
    fn repo(&self) -> Result<PathBuf> {
        Ok(if self.has("repo-root") {
            PathBuf::from(self.get("repo-root", ""))
        } else {
            std::env::current_dir()?
        })
    }
}
async fn prompt(label: &str, hidden: bool) -> Result<String> {
    let mut tty = std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .custom_flags(rustix::fs::OFlags::NONBLOCK.bits() as i32)
        .open("/dev/tty")?;
    let guard = if hidden {
        Some(Echo::hide(&tty)?)
    } else {
        None
    };
    write!(tty, "{label}")?;
    tty.flush()?;
    // The owned fd stays stable while registered. Canonical terminal input is
    // observed asynchronously so the entry point can cancel and restore state.
    #[allow(
        deprecated,
        reason = "safe owned-descriptor API retained until its replacement is available"
    )]
    let terminal = tokio::io::unix::AsyncFd::new(tty)?;
    let mut line = Vec::new();
    loop {
        let mut ready = terminal.readable().await?;
        let mut buffer = [0u8; 4096];
        match ready
            .try_io(|fd| rustix::io::read(fd.get_ref(), &mut buffer).map_err(std::io::Error::from))
        {
            Err(_) => continue,
            Ok(result) => {
                let count = result?;
                line.extend_from_slice(&buffer[..count]);
                if count == 0 || line.contains(&b'\n') {
                    break;
                }
            }
        }
    }
    drop(guard);
    Ok(String::from_utf8(line)?
        .trim_end_matches(['\r', '\n'])
        .to_owned())
}
struct Echo {
    tty: std::fs::File,
    original: rustix::termios::Termios,
}
impl Echo {
    fn hide(tty: &std::fs::File) -> Result<Self> {
        let original = rustix::termios::tcgetattr(tty)?;
        let guard = Self {
            tty: tty.try_clone()?,
            original,
        };
        let mut hidden = guard.original.clone();
        hidden
            .local_modes
            .remove(rustix::termios::LocalModes::ECHO | rustix::termios::LocalModes::ECHONL);
        rustix::termios::tcsetattr(tty, rustix::termios::OptionalActions::Now, &hidden)?;
        Ok(guard)
    }
}
impl Drop for Echo {
    fn drop(&mut self) {
        let _restore_result = rustix::termios::tcsetattr(
            &self.tty,
            rustix::termios::OptionalActions::Flush,
            &self.original,
        );
        let _terminal_result = writeln!(self.tty);
    }
}
async fn dispatch(name: &str) -> Result<()> {
    if name.ends_with("worker") {
        let mut raw = String::new();
        tokio::io::AsyncReadExt::read_to_string(&mut tokio::io::stdin(), &mut raw).await?;
        return sealed::worker(name, serde_json::from_str(&raw)?).await;
    }
    let args = match Args::parse(name) {
        Ok(args) => args,
        Err(_) => {
            eprintln!("{name}: invalid arguments; use --help");
            std::process::exit(2);
        }
    };
    if args.has("help") {
        println!(
            "{name}: native credential maintenance; options: --plan --bootstrap-plan --identity --authorizer-key --administrator-host --repo-root (setup); --credential-via-host --only --dry-run --apply --receipt (import); --session-file --identity-url --wardrobe-url --realm (identity); --prompt --seal-only (Miniflux)"
        );
        return Ok(());
    }
    match name {
        "homelab-to-bitwarden" | "freshrss-to-bitwarden" => {
            inventory::main(&args, name.starts_with("freshrss")).await
        }
        "miniflux-to-bitwarden" => setup::miniflux(&args).await,
        "identity-to-bitwarden" => setup::identity(&args).await,
        _ => fail("unknown command"),
    }
}
async fn guarded(name: &str) -> Result<i32> {
    use tokio::signal::unix::{SignalKind, signal};
    // Subscribe before either a password prompt or an owned child is created.
    let mut interrupt = signal(SignalKind::interrupt())?;
    let mut terminate = signal(SignalKind::terminate())?;
    let mut hangup = signal(SignalKind::hangup())?;
    let mut quit = signal(SignalKind::quit())?;
    tokio::select! {
        result = dispatch(name) => result.map(|()| 0),
        _ = interrupt.recv() => Ok(130),
        _ = terminate.recv() => Ok(143),
        _ = hangup.recv() => Ok(129),
        _ = quit.recv() => Ok(131),
    }
}
pub fn cli(name: &str) {
    let runtime = match tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
    {
        Ok(runtime) => runtime,
        Err(_) => {
            eprintln!("{name}: could not initialize credential maintenance");
            std::process::exit(1);
        }
    };
    let result = runtime.block_on(guarded(name));
    // Tokio's stdin reader may be blocking while a remote sender holds its
    // pipe open. Process exit owns that thread; never wait for it after cancel.
    runtime.shutdown_background();
    match result {
        Ok(status) => std::process::exit(status),
        Err(_) => {
            eprintln!("{name}: operation failed; sensitive output suppressed");
            std::process::exit(1);
        }
    }
}
