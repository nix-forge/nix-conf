use music_api_tools::{Result, client, credential, field, finish, request};
use reqwest::Method;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    fs::{self, OpenOptions},
    io::Write,
    os::unix::fs::OpenOptionsExt,
    path::Path,
    time::Duration,
};
async fn run() -> Result<()> {
    let args: Vec<_> = std::env::args_os().skip(1).collect();
    let [receipt] = args.as_slice() else {
        return Err("receipt required".into());
    };
    let receipt = Path::new(receipt);
    match fs::remove_file(receipt) {
        Ok(()) => {}
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
        Err(e) => return Err(e.into()),
    }
    let account: Value = serde_json::from_str(&credential("listenbrainz-identity")?)?;
    let token = account
        .get("token")
        .and_then(Value::as_str)
        .unwrap_or("")
        .trim();
    if token.is_empty() {
        return Ok(());
    }
    let username = field(&account, "listenbrainzUsername")?.trim();
    let client = client(Duration::from_secs(10), false)?;
    let response = request(
        &client,
        "https://api.listenbrainz.org/1/validate-token",
        Method::GET,
        None,
        &[("Authorization", &format!("Token {token}"))],
    )
    .await?;
    if username.is_empty()
        || response.get("valid").and_then(Value::as_bool) != Some(true)
        || field(&response, "user_name")? != username
    {
        return Err("ListenBrainz token owner mismatch".into());
    }
    let fingerprint = format!(
        "{}",
        base16ct::HexDisplay(&Sha256::digest(format!("{username}\0{token}").as_bytes()))
    );
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o400)
        .open(receipt)?;
    writeln!(
        file,
        "{}",
        json!({"username":username,"fingerprint":fingerprint})
    )?;
    file.sync_all()?;
    Ok(())
}
#[tokio::main(flavor = "current_thread")]
async fn main() -> std::process::ExitCode {
    finish(run().await, "ListenBrainz identity validation failed")
}
