//! Gate exec until Chromium's exact PID scope policy has been published.
use serde_json::{Value, json};
use std::{
    env,
    fs::{self, OpenOptions},
    io::{Read, Write},
    os::unix::{
        fs::{DirBuilderExt, MetadataExt, OpenOptionsExt},
        process::CommandExt,
    },
    path::{Path, PathBuf},
    time::Duration,
};
use tokio::{io::AsyncWriteExt, net::UnixListener, process::Command};
type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
const POLICY: &str = "90-codex-slice.conf";
async fn systemctl(args: &[&str]) -> Result<std::process::Output> {
    Ok(nix_conf_process::run(
        Command::new("systemctl").arg("--user").args(args),
        None,
        Duration::from_secs(15),
    )
    .await?)
}
async fn cleanup(state: &Path, runtime: &Path, stop: bool) -> Result<()> {
    let record = state.join("policy.json");
    let ownership: Value = match fs::read(&record) {
        Ok(bytes) => serde_json::from_slice(&bytes)?,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(e) => return Err(e.into()),
    };
    let policy = PathBuf::from(ownership["path"].as_str().ok_or("Invalid ownership path")?);
    if policy.file_name().and_then(|v| v.to_str()) != Some(POLICY)
        || policy.parent().and_then(Path::parent) != Some(runtime.join("systemd/user").as_path())
    {
        return Err("Invalid launch ownership record".into());
    }
    let content = ownership["content"]
        .as_str()
        .ok_or("Invalid ownership content")?;
    match fs::read_to_string(&policy) {
        Ok(actual) if actual == content => {
            if stop {
                let directory = policy
                    .parent()
                    .and_then(Path::file_name)
                    .and_then(|v| v.to_str())
                    .ok_or("Invalid scope directory")?;
                let unit = directory.strip_suffix(".d").ok_or("Invalid scope unit")?;
                let status =
                    systemctl(&["show", "--property=ActiveState", "--value", unit]).await?;
                if ["active", "activating", "deactivating"]
                    .contains(&String::from_utf8_lossy(&status.stdout).trim())
                    && !systemctl(&["stop", unit]).await?.status.success()
                {
                    return Err("Scope stop failed".into());
                }
            }
            fs::remove_file(&policy)?;
            if let Some(parent) = policy.parent() {
                let _cleanup_result = fs::remove_dir(parent);
            }
        }
        Ok(_) => (),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => (),
        Err(e) => return Err(e.into()),
    }
    fs::remove_file(record)?;
    let _reload_result = systemctl(&["daemon-reload"]).await;
    Ok(())
}
fn exclusive(path: &Path, bytes: &[u8]) -> Result<()> {
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(path)?;
    file.write_all(bytes)?;
    Ok(())
}
async fn supervise(args: &[String]) -> Result<i32> {
    if args.is_empty() {
        return Err("Missing command".into());
    }
    let runtime = PathBuf::from(env::var("XDG_RUNTIME_DIR")?);
    if fs::metadata(&runtime)?.uid() != rustix::process::getuid().as_raw() {
        return Err("Foreign runtime directory".into());
    }
    let production = env::var_os("RUNTIME_DIRECTORY").is_some();
    let state = env::var_os("RUNTIME_DIRECTORY")
        .map(PathBuf::from)
        .unwrap_or_else(|| runtime.join(format!("codex-launch-{}", std::process::id())));
    fs::DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(&state)?;
    let socket = state.join("exec-gate.sock");
    let listener = UnixListener::bind(&socket)?;
    let mut child = Command::new(env::current_exe()?)
        .arg("exec")
        .arg(&socket)
        .args(args)
        .kill_on_drop(true)
        .spawn()?;
    let pid = child.id().ok_or("Missing child PID")?;
    let directory = runtime.join(format!(
        "systemd/user/app-org.chromium.Chromium-{pid}.scope.d"
    ));
    let policy = directory.join(POLICY);
    let result=async {
        let (mut gate,_)=tokio::time::timeout(Duration::from_secs(15),listener.accept()).await??;
        let binding=match env::var("CODEX_LAUNCH_UNIT"){Ok(unit)=>{if unit.contains(['\n','\r']){return Err("Invalid launch unit".into());}format!("[Unit]\nBindsTo={unit}\nAfter={unit}\n")},Err(_)=>String::new()};
        let content=format!("# Owned Codex launch policy\n{binding}[Scope]\nSlice=app-codex.slice\nOOMPolicy=continue\nTimeoutStopSec=5s\nMemoryHigh=infinity\nMemoryMax=infinity\nMemorySwapMax=infinity\n");
        fs::create_dir_all(&directory)?;
        exclusive(&state.join("policy.json"),&serde_json::to_vec(&json!({"path":policy,"content":content}))?)?;
        let prepared=state.join("scope.conf");exclusive(&prepared,content.as_bytes())?;fs::hard_link(prepared,&policy)?;
        if !systemctl(&["daemon-reload"]).await?.status.success(){return Err("Policy reload failed".into());}
        gate.write_all(b"1").await?;drop(gate);
        let mut term=tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())?;
        let mut hup=tokio::signal::unix::signal(tokio::signal::unix::SignalKind::hangup())?;
        let mut int=tokio::signal::unix::signal(tokio::signal::unix::SignalKind::interrupt())?;
        loop {
            let signal=tokio::select!{status=child.wait()=>return Ok::<i32,Box<dyn std::error::Error>>({use std::os::unix::process::ExitStatusExt;let status=status?;status.code().unwrap_or_else(||128+status.signal().unwrap_or(1))}),_=term.recv()=>rustix::process::Signal::TERM,_=hup.recv()=>rustix::process::Signal::HUP,_=int.recv()=>rustix::process::Signal::INT};
            if let Some(pid)=rustix::process::Pid::from_raw(pid as i32){let _signal_result = rustix::process::kill_process(pid,signal);}
        }
    }.await;
    if result.is_err() {
        let _kill_result = child.kill().await;
    }
    let _cleanup_result = fs::remove_file(socket);
    // ExecStopPost retains BindsTo until it has stopped the migrated scope.
    if !production {
        cleanup(&state, &runtime, false).await?;
    }
    result
}
#[tokio::main(flavor = "current_thread")]
async fn main() {
    let args: Vec<_> = env::args().skip(1).collect();
    let result = if args.first().is_some_and(|s| s == "exec") {
        (|| -> Result<i32> {
            if args.len() < 3 {
                return Err("Missing exec gate".into());
            }
            let mut gate = std::os::unix::net::UnixStream::connect(&args[1])?;
            let mut token = [0];
            gate.read_exact(&mut token)?;
            drop(gate);
            if token != *b"1" {
                return Err("Gate closed".into());
            }
            let error = std::process::Command::new(&args[2]).args(&args[3..]).exec();
            Err(error.into())
        })()
    } else if args.first().is_some_and(|s| s == "cleanup") {
        match (env::var("RUNTIME_DIRECTORY"), env::var("XDG_RUNTIME_DIR")) {
            (Ok(state), Ok(runtime)) => cleanup(Path::new(&state), Path::new(&runtime), true)
                .await
                .map(|_| 0),
            _ => Err("Missing runtime directory".into()),
        }
    } else {
        supervise(&args).await
    };
    match result {
        Ok(code) => std::process::exit(code),
        Err(_) => {
            eprintln!(
                "Codex launch failed; scope ownership and runtime policy retained for recovery"
            );
            std::process::exit(1);
        }
    }
}
