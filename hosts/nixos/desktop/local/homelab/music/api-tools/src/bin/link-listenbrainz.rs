use music_api_tools::{Result, client, field, finish, request};
use reqwest::Method;
use serde_json::{Value, json};
use std::{fs, time::Duration};
async fn run() -> Result<()> {
    let args: Vec<_> = std::env::args().skip(1).collect();
    if !(3..=4).contains(&args.len()) {
        return Err("port, account, password and optional username required".into());
    }
    let base = format!("http://127.0.0.1:{}", args[0].parse::<u16>()?);
    let account: Value = serde_json::from_slice(&fs::read(&args[1])?)?;
    let username = match args.get(3) {
        Some(s) => s.as_str(),
        None => field(&account, "navidromeUsername")?,
    };
    let password = fs::read_to_string(&args[2])?;
    let client = client(Duration::from_secs(15), true)?;
    let login = request(
        &client,
        &format!("{base}/auth/login"),
        Method::POST,
        Some(&json!({"username":username,"password":password.trim()})),
        &[],
    )
    .await?;
    let token = format!("Bearer {}", field(&login, "token")?);
    let linked = request(
        &client,
        &format!("{base}/api/listenbrainz/link"),
        Method::PUT,
        Some(&json!({"token":field(&account,"token")?})),
        &[("X-ND-Authorization", &token)],
    )
    .await?;
    if linked.get("status").and_then(Value::as_bool) != Some(true)
        || field(&linked, "user")? != field(&account, "listenbrainzUsername")?
    {
        return Err("ListenBrainz account mismatch".into());
    }
    Ok(())
}
#[tokio::main(flavor = "current_thread")]
async fn main() -> std::process::ExitCode {
    finish(
        run().await,
        "Unable to link ListenBrainz scrobbling for the managed listener",
    )
}
