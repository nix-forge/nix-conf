//! Native macOS boundaries with one child deadline covering capture and exit.
use std::{io, process::Output, time::Duration};
pub type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
pub async fn run(program: &str, args: &[&str]) -> Result<Output> {
    Ok(nix_conf_process::run(
        tokio::process::Command::new(program).args(args),
        None,
        Duration::from_secs(35),
    )
    .await?)
}
pub async fn checked(program: &str, args: &[&str]) -> Result<Output> {
    let result = run(program, args).await?;
    if !result.status.success() {
        return Err(io::Error::other(format!("Native command failed: {program}")).into());
    }
    Ok(result)
}
pub fn fail<T>(message: &str) -> Result<T> {
    Err(io::Error::other(message).into())
}
