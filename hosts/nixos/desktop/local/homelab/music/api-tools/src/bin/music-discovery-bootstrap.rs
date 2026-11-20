//! Reconcile service accounts and private plugin policy through native interfaces.
use music_api_tools::{Result, account_pty, client, field};
use serde_json::{Value, json};
use std::{
    env, fs,
    io::Write,
    path::{Path, PathBuf},
    time::Duration,
};
use tokio::process::Command;
async fn command(policy: &Value, args: &[&str], environment: &[(&str, &str)]) -> Result<Vec<u8>> {
    let mut child = Command::new(field(policy, "navidrome")?);
    child
        .args(["--configfile", field(policy, "navidromeConfig")?])
        .args(args)
        .envs(environment.iter().copied());
    let out = nix_conf_process::run(&mut child, None, Duration::from_secs(60)).await?;
    if !out.status.success() {
        return Err("Navidrome command failed".into());
    }
    Ok(out.stdout)
}
async fn helper(
    policy: &Value,
    key: &str,
    args: &[&str],
    environment: &[(&str, &str)],
) -> Result<()> {
    let mut child = Command::new(field(policy, key)?);
    child.args(args).envs(environment.iter().copied());
    let out = nix_conf_process::run(&mut child, None, Duration::from_secs(60)).await?;
    if !out.status.success() {
        return Err("service helper failed".into());
    }
    Ok(())
}
fn has_user(accounts: &Value, name: &str) -> Result<bool> {
    Ok(accounts
        .as_array()
        .ok_or("invalid account list")?
        .iter()
        .any(|account| {
            ["userName", "username", "UserName"]
                .into_iter()
                .find_map(|key| account.get(key).filter(|v| !v.is_null()))
                .and_then(Value::as_str)
                == Some(name)
        }))
}
fn user_ids(accounts: &Value, names: [&str; 2]) -> Result<String> {
    let accounts = accounts.as_array().ok_or("invalid account list")?;
    let mut ids = Vec::new();
    for name in names {
        let matches: Vec<_> = accounts.iter().filter(|a| a["username"] == name).collect();
        if matches.len() != 1 {
            return Err("expected exactly one managed account".into());
        }
        let id = field(matches[0], "id")?;
        if id.is_empty() {
            return Err("managed account has no ID".into());
        }
        ids.push(id);
    }
    if ids[0] == ids[1] {
        return Err("managed accounts share an ID".into());
    }
    Ok(serde_json::to_string(&ids)?)
}
fn credential(root: &Path, name: &str) -> Result<String> {
    Ok(fs::read_to_string(root.join(name))?
        .trim_end_matches('\n')
        .into())
}
fn private_config(root: &Path, value: &Value) -> Result<tempfile::NamedTempFile> {
    let mut file = tempfile::NamedTempFile::new_in(root)?;
    serde_json::to_writer(&mut file, value)?;
    file.flush()?;
    Ok(file)
}
async fn reconcile(policy: &Value) -> Result<()> {
    let credentials =
        PathBuf::from(env::var_os("CREDENTIALS_DIRECTORY").ok_or("missing credential directory")?);
    let runtime =
        PathBuf::from(env::var_os("RUNTIME_DIRECTORY").ok_or("missing runtime directory")?);
    let port = policy["port"]
        .as_u64()
        .and_then(|p| u16::try_from(p).ok())
        .ok_or("invalid port")?
        .to_string();
    let client = client(Duration::from_secs(3), true)?;
    // This HTTP service exposes no host readiness notification. Retry only the
    // idempotent ping, with positive delay, within one deadline.
    tokio::time::timeout(Duration::from_secs(105), async {
        for attempt in 0..=20 {
            if client
                .get(format!("http://127.0.0.1:{port}/ping"))
                .send()
                .await
                .is_ok_and(|r| r.status().is_success())
            {
                return Ok::<_, Box<dyn std::error::Error>>(());
            }
            if attempt != 20 {
                tokio::time::sleep(Duration::from_secs(2)).await;
            }
        }
        Err("Navidrome did not become ready".into())
    })
    .await??;
    let admin = credential(&credentials, "navidrome-admin-username")?;
    let service = credential(&credentials, "navidrome-service-username")?;
    let feishin = credential(&credentials, "feishin-listener-username")?;
    let mut users: Value = serde_json::from_slice(
        &command(policy, &["user", "list", "--format", "json"], &[]).await?,
    )?;
    let config = field(policy, "navidromeConfig")?;
    for (name, password, role) in [
        (&admin, env::var("NAVIDROME_ADMIN_PASSWORD")?, "admin"),
        (&service, env::var("NAVIDROME_SERVICE_PASSWORD")?, "regular"),
        (
            &feishin,
            credential(&credentials, "feishin-listener-password")?,
            "regular",
        ),
    ] {
        if !has_user(&users, name)? {
            if account_pty::create(std::ffi::OsStr::new(config), name, &password, role).await? != 0
            {
                return Err("account creation failed".into());
            }
            if role == "admin" {
                users = serde_json::from_slice(
                    &command(policy, &["user", "list", "--format", "json"], &[]).await?,
                )?;
            }
        }
    }
    let identity_path = credentials.join("listenbrainz-identity");
    let identity: Value = serde_json::from_slice(&fs::read(&identity_path)?)?;
    let listener = field(&identity, "navidromeUsername")?;
    if listener.is_empty() {
        return Err("managed listener is empty".into());
    }
    if !has_user(&users, listener)?
        && account_pty::create(
            std::ffi::OsStr::new(config),
            listener,
            &credential(&credentials, "listenbrainz-listener-password")?,
            "regular",
        )
        .await?
            != 0
    {
        return Err("listener creation failed".into());
    }
    users = serde_json::from_slice(
        &command(policy, &["user", "list", "--format", "json"], &[]).await?,
    )?;
    let ids = user_ids(&users, [listener, &feishin])?;
    let identity_path = identity_path
        .to_str()
        .ok_or("credential path is not UTF-8")?;
    let admin_environment = [("NAVIDROME_ADMIN_USERNAME", admin.as_str())];
    for (name, password) in [
        (None, "listenbrainz-listener-password"),
        (Some(feishin.as_str()), "feishin-listener-password"),
    ] {
        let password = credentials.join(password);
        let password = password.to_str().ok_or("credential path is not UTF-8")?;
        let mut args = vec![port.as_str(), identity_path, password];
        if let Some(name) = name {
            args.push(name);
        }
        if helper(policy, "linkListenBrainz", &args, &admin_environment)
            .await
            .is_err()
        {
            eprintln!(
                "ListenBrainz scrobbling could not be linked; check the managed listener credentials"
            );
        }
    }
    command(policy, &["plugin", "rescan"], &[]).await?;
    helper(
        policy,
        "configureLyrics",
        &[&port, field(policy, "lyricsConfig")?],
        &admin_environment,
    )
    .await?;
    let lbz = field(&identity, "listenbrainzUsername")?;
    let token = field(&identity, "token")?;
    if lbz.is_empty() || token.is_empty() {
        return Err("ListenBrainz identity is incomplete".into());
    }
    let users = [listener,feishin.as_str()].map(|name| json!({"username":name,"lbzUsername":lbz,"lbzToken":token,"generatePlaylist":false,"ratings":["0","1","2","3","4","5"],"sources":[{"sourcePatch":"daily-jams","playlistName":"ListenBrainz Daily Jams"},{"sourcePatch":"weekly-jams","playlistName":"ListenBrainz Weekly Jams"},{"sourcePatch":"weekly-exploration","playlistName":"ListenBrainz Weekly Exploration"}]}));
    let playlist = private_config(
        &runtime,
        &json!({"schedule":8,"checkOnStartup":true,"users":users}),
    )?;
    command(
        policy,
        &[
            "plugin",
            "edit",
            "listenbrainz-daily-playlist",
            "--config-file",
            playlist
                .path()
                .to_str()
                .ok_or("runtime path is not UTF-8")?,
            "--users",
            &ids,
            "--all-libraries",
            "--no-write-access",
        ],
        &[],
    )
    .await?;
    command(
        policy,
        &["plugin", "enable", "listenbrainz-daily-playlist"],
        &[],
    )
    .await?;
    let audio_port = policy["audioMusePort"]
        .as_u64()
        .and_then(|p| u16::try_from(p).ok())
        .ok_or("invalid AudioMuse port")?;
    let audio = private_config(
        &runtime,
        &json!({"apiUrl":format!("http://127.0.0.1:{audio_port}"),"apiToken":credential(&credentials,"audiomuse-api-token")?,"artistSimilarCount":20,"instantMixSource":"similarSong","eliminateDuplicates":true,"radiusSimilarity":true}),
    )?;
    command(
        policy,
        &[
            "plugin",
            "edit",
            "audiomuseai",
            "--config-file",
            audio.path().to_str().ok_or("runtime path is not UTF-8")?,
            "--users",
            &service,
            "--all-libraries",
            "--no-write-access",
        ],
        &[],
    )
    .await?;
    if fs::File::open(field(policy, "householdApproval")?).is_ok() {
        command(
            policy,
            &[
                "plugin",
                "edit",
                "audiomuseai",
                "--all-users",
                "--all-libraries",
                "--no-write-access",
            ],
            &[],
        )
        .await?;
        command(policy, &["plugin", "enable", "audiomuseai"], &[]).await?;
    } else {
        command(policy, &["plugin", "disable", "audiomuseai"], &[]).await?;
        println!("AudioMuse plugin remains disabled pending household isolation approval");
    }
    Ok(())
}
async fn run() -> Result<()> {
    let args: Vec<_> = env::args_os().skip(1).collect();
    if args.len() != 1 {
        return Err("policy required".into());
    }
    let policy = serde_json::from_slice(&fs::read(&args[0])?)?;
    tokio::time::timeout(Duration::from_secs(300), reconcile(&policy)).await?
}
async fn guarded() -> Result<u8> {
    use tokio::signal::unix::{SignalKind, signal};
    let mut term = signal(SignalKind::terminate())?;
    let mut interrupt = signal(SignalKind::interrupt())?;
    let mut hangup = signal(SignalKind::hangup())?;
    let mut quit = signal(SignalKind::quit())?;
    tokio::select! { result = run() => result.map(|()|0), _=term.recv()=>Ok(143), _=interrupt.recv()=>Ok(130), _=hangup.recv()=>Ok(129), _=quit.recv()=>Ok(131) }
}
#[tokio::main(flavor = "current_thread")]
async fn main() -> std::process::ExitCode {
    match guarded().await {
        Ok(code) => std::process::ExitCode::from(code),
        Err(_) => {
            eprintln!("Music discovery bootstrap failed; private diagnostics suppressed");
            std::process::ExitCode::FAILURE
        }
    }
}
