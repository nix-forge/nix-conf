//! Private CLI adapter; the bootstrap also calls the same PTY implementation directly.
use music_api_tools::{Result, account_pty};
async fn run() -> Result<u8> {
    let args: Vec<_> = std::env::args_os().skip(1).collect();
    if args.len() != 1 {
        return Err("configuration required".into());
    }
    account_pty::create(
        &args[0],
        &std::env::var("MUSIC_DISCOVERY_USERNAME")?,
        &std::env::var("MUSIC_DISCOVERY_PASSWORD")?,
        &std::env::var("MUSIC_DISCOVERY_ROLE")?,
    )
    .await
}
#[tokio::main(flavor = "current_thread")]
async fn main() -> std::process::ExitCode {
    match run().await {
        Ok(code) => std::process::ExitCode::from(code),
        Err(_) => {
            eprintln!("Navidrome account creation failed (private PTY exchange).");
            std::process::ExitCode::FAILURE
        }
    }
}
