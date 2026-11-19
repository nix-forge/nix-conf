use serde_json::Value;
use std::{env, time::Duration};
async fn clients() -> Result<Value, Box<dyn std::error::Error>> {
    let output = nix_conf_process::run(
        tokio::process::Command::new("hyprctl").args(["-j", "clients"]),
        None,
        Duration::from_secs(2),
    )
    .await?;
    if !output.status.success() {
        return Err("hyprctl failed".into());
    }
    Ok(serde_json::from_slice(&output.stdout)?)
}
#[tokio::main(flavor = "current_thread")]
async fn main() {
    let mut args = env::args().skip(1);
    let action = args.next().unwrap_or_default();
    if action != "screen" && action != "suspend" {
        eprintln!("usage: desktop-idle-inhibitor screen|suspend [--] [BACKGROUND_CLASS ...]");
        std::process::exit(2);
    }
    let mut ignored = args.collect::<Vec<_>>();
    if ignored.first().is_some_and(|s| s == "--") {
        ignored.remove(0);
    }
    let result = clients().await.and_then(|value| {
        let clients = value.as_array().ok_or("invalid clients response")?;
        if clients
            .iter()
            .any(|c| !c.is_object() || !c["class"].is_string() || !c["inhibitingIdle"].is_boolean())
        {
            return Err("invalid clients response".into());
        }
        Ok(clients.iter().any(|c| {
            c["inhibitingIdle"] == true
                && !(action == "screen" && ignored.iter().any(|s| c["class"] == *s))
        }))
    });
    let inhibit = match result {
        Ok(b) => b,
        Err(e) => {
            eprintln!("Cannot inspect native idle inhibitors: {e}");
            action == "suspend"
        }
    };
    std::process::exit(i32::from(inhibit));
}
