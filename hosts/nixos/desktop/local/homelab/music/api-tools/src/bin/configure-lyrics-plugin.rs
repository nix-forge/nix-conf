use music_api_tools::{Result, client, field, finish, request};
use reqwest::Method;
use serde_json::json;
use std::{fs, time::Duration};
async fn run() -> Result<()> {
    let args: Vec<_> = std::env::args().skip(1).collect();
    let [port, config] = args.as_slice() else {
        return Err("port and config required".into());
    };
    let base = format!("http://127.0.0.1:{}", port.parse::<u16>()?);
    let client = client(Duration::from_secs(15), true)?;
    let login=request(&client,&format!("{base}/auth/login"),Method::POST,Some(&json!({"username":std::env::var("NAVIDROME_ADMIN_USERNAME")?,"password":std::env::var("NAVIDROME_ADMIN_PASSWORD")?})),&[]).await?;
    let token = format!("Bearer {}", field(&login, "token")?);
    let headers = [("X-ND-Authorization", token.as_str())];
    request(
        &client,
        &format!("{base}/api/plugin/rescan"),
        Method::POST,
        Some(&json!({})),
        &headers,
    )
    .await?;
    let plugin=request(&client,&format!("{base}/api/plugin/nd-lyrics"),Method::PUT,Some(&json!({"config":fs::read_to_string(config)?,"allUsers":true,"allLibraries":true,"allowWriteAccess":false,"enabled":true})),&headers).await?;
    if plugin.get("enabled").and_then(serde_json::Value::as_bool) != Some(true) {
        return Err("lyrics plugin not enabled".into());
    }
    Ok(())
}
#[tokio::main(flavor = "current_thread")]
async fn main() -> std::process::ExitCode {
    finish(run().await, "Unable to enable the managed lyrics plugin")
}
