use music_api_tools::{Result, client, credential, finish, request};
use reqwest::Method;
use serde_json::{Value, json};
use std::time::Duration;
async fn run() -> Result<()> {
    let key = credential("lidarr-api-key")?;
    if key.contains(['\r', '\n']) {
        return Err("invalid API header".into());
    }
    let timeout = std::env::var("HTTP_TIMEOUT_SECONDS")?.parse::<u64>()?;
    let budget = std::env::var("HTTP_RETRY_BUDGET_SECONDS")?.parse::<u64>()?;
    let attempts = std::env::var("HTTP_RETRY_ATTEMPTS")?.parse::<u64>()?;
    if timeout == 0 || budget == 0 {
        return Err("HTTP deadlines must be positive".into());
    }
    let base = format!("{}/api/v1", std::env::var("LIDARR_URL")?);
    let mut command = tokio::process::Command::new(std::env::var_os("CURL").ok_or("curl missing")?);
    command.args([
        "--silent",
        "--show-error",
        "--fail",
        "--noproxy",
        "*",
        "--max-time",
        &timeout.to_string(),
        "--retry",
        &attempts.to_string(),
        "--retry-connrefused",
        "--retry-max-time",
        &budget.to_string(),
        "--header",
        "@-",
        &format!("{base}/command"),
    ]);
    let deadline = budget
        .checked_add(timeout)
        .and_then(|s| s.checked_add(5))
        .ok_or("invalid HTTP deadline")?;
    // Curl owns safe GET retries/backoff. Credential is sent through private stdin.
    let output = nix_conf_process::run(
        &mut command,
        Some(format!("X-Api-Key: {key}\n").as_bytes()),
        Duration::from_secs(deadline),
    )
    .await?;
    if !output.status.success() {
        return Err("Lidarr status query failed".into());
    }
    let commands: Value = serde_json::from_slice(&output.stdout)?;
    let commands = commands.as_array().ok_or("invalid Lidarr commands")?;
    let scanning = commands.iter().any(|v| {
        v.get("name").and_then(Value::as_str) == Some("RescanFolders")
            && matches!(
                v.get("status").and_then(Value::as_str),
                Some("queued" | "started")
            )
    });
    if !scanning {
        request(
            &client(Duration::from_secs(timeout), true)?,
            &format!("{base}/command"),
            Method::POST,
            Some(&json!({"name":"RescanFolders","folders":[std::env::var("MUSIC_ROOT")?]})),
            &[("X-Api-Key", &key)],
        )
        .await?;
        println!("Shared music library rescan queued");
    }
    Ok(())
}
#[tokio::main(flavor = "current_thread")]
async fn main() -> std::process::ExitCode {
    finish(
        run().await,
        "Unable to reconcile the shared music library scan",
    )
}
