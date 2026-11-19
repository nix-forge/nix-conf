use music_api_tools::{Result, client, credential, field, finish, request};
use reqwest::Method;
use serde_json::{Value, json};
use std::time::{Duration, Instant};
fn endpoint(settings: &Value) -> Result<&str> {
    for kind in ["basic_fields", "advanced_fields"] {
        for value in settings
            .get(kind)
            .and_then(Value::as_array)
            .ok_or("invalid AudioMuse setup fields")?
        {
            if value.get("name").and_then(Value::as_str) == Some("NAVIDROME_URL") {
                return field(value, "value");
            }
        }
    }
    Err("AudioMuse setup does not expose Navidrome endpoint".into())
}
async fn run() -> Result<()> {
    let args: Vec<_> = std::env::args().skip(1).collect();
    let [desired] = args.as_slice() else {
        return Err("Navidrome endpoint required".into());
    };
    let token = format!("Bearer {}", credential("api-token")?);
    let headers = [("Authorization", token.as_str())];
    let url = "http://127.0.0.1:8000/api/setup";
    let client = client(Duration::from_secs(20), true)?;
    let current = request(&client, url, Method::GET, None, &headers).await?;
    let changed = endpoint(&current)?.trim_end_matches('/') != desired.trim_end_matches('/');
    if changed {
        let probe = request(
            &client,
            url,
            Method::POST,
            Some(&json!({"config":{"NAVIDROME_URL":desired},"test_connection":true})),
            &headers,
        )
        .await?;
        if probe.get("status").and_then(Value::as_str) != Some("ok") {
            return Err("AudioMuse endpoint probe failed".into());
        }
        request(
            &client,
            url,
            Method::POST,
            Some(&json!({"config":{"NAVIDROME_URL":desired}})),
            &headers,
        )
        .await?;
        // This HTTP API has no readiness notifications. Only safe GET is retried;
        // saving restarts workers, so the mutation is never repeated here.
        let deadline = Instant::now() + Duration::from_secs(60);
        loop {
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining <= Duration::from_secs(2) {
                return Err("AudioMuse restart deadline exceeded".into());
            }
            tokio::time::sleep(Duration::from_secs(2)).await;
            let remaining = deadline.saturating_duration_since(Instant::now());
            if let Ok(Ok(value)) = tokio::time::timeout(
                remaining,
                request(&client, url, Method::GET, None, &headers),
            )
            .await
                && endpoint(&value)
                    .is_ok_and(|v| v.trim_end_matches('/') == desired.trim_end_matches('/'))
            {
                break;
            }
        }
    }
    println!("{}", json!({"changed":changed,"verified":true}));
    Ok(())
}
#[tokio::main(flavor = "current_thread")]
async fn main() -> std::process::ExitCode {
    finish(run().await, "AudioMuse endpoint reconciliation failed")
}
