use std::{
    env,
    process::{Command, Stdio},
};
type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
fn command(program: &str, args: &[&str], quiet: bool) -> Result<bool> {
    let mut command = Command::new(program);
    command.args(args);
    if quiet {
        command.stdout(Stdio::null()).stderr(Stdio::null());
    }
    Ok(command.status()?.success())
}
fn required(program: &str, args: &[&str]) -> Result<()> {
    use std::os::unix::process::ExitStatusExt;
    let status = Command::new(program).args(args).status()?;
    if !status.success() {
        std::process::exit(
            status
                .code()
                .unwrap_or_else(|| 128 + status.signal().unwrap_or(1)),
        );
    }
    Ok(())
}
fn vault() -> Result<()> {
    rustix::process::umask(rustix::fs::Mode::from_bits_truncate(0o077));
    if !rustix::process::geteuid().is_root() {
        eprintln!("Run as root with sudo.");
        std::process::exit(1);
    }
    match env::args_os().nth(1).as_deref().and_then(|s| s.to_str()) {
        Some("unlock") => {
            required(
                "systemctl",
                &[
                    "reset-failed",
                    "actual-vault-open.service",
                    "srv-actual.mount",
                    "actual.service",
                ],
            )?;
            required("systemctl", &["start", "actual.service", "actual.timer"])?;
        }
        Some("lock") => {
            required(
                "systemctl",
                &[
                    "stop",
                    "actual.timer",
                    "actual.service",
                    "actual-vault-ready.service",
                ],
            )?;
            if command("mountpoint", &["-q", "/srv/actual"], false)? {
                required("systemctl", &["stop", "srv-actual.mount"])?;
            }
            if command("cryptsetup", &["status", "actual-vault"], true)? {
                required("cryptsetup", &["close", "actual-vault"])?;
            }
            required("systemctl", &["stop", "actual-vault-open.service"])?;
        }
        Some("status") => {
            // Status is diagnostic: attempt every probe, regardless of failures.
            let _diagnostic_result = command("cryptsetup", &["status", "actual-vault"], false);
            let _diagnostic_result = command("findmnt", &["/srv/actual"], false);
            let _diagnostic_result = command(
                "systemctl",
                &["--no-pager", "status", "actual.service"],
                false,
            );
        }
        _ => {
            eprintln!("Usage: actual-vault {{unlock|lock|status}}");
            std::process::exit(2);
        }
    }
    Ok(())
}
fn main() {
    if vault().is_err() {
        eprintln!("Actual vault command failed");
        std::process::exit(1);
    }
}
