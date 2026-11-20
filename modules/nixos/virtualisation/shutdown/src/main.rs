//! Graceful guest shutdown with registered lifecycle events and one timer.
// The maintained safe virt crate lacks lifecycle registration. Keep its stable
// C ABI in a small audited boundary rather than replacing readiness with polls.
#[cfg(target_os = "linux")]
#[allow(
    unsafe_code,
    reason = "native ABI adapter with locally documented ownership and lifetimes"
)]
mod native;
#[cfg(target_os = "linux")]
fn run() -> Result<(), Box<dyn std::error::Error>> {
    let mut args = std::env::args().skip(1);
    let mut timeout = 300u64;
    let mut position = Vec::new();
    while let Some(arg) = args.next() {
        if arg == "--timeout" {
            timeout = args.next().ok_or("timeout required")?.parse()?;
            continue;
        }
        if arg.starts_with('-') {
            return Err("invalid argument".into());
        }
        position.push(arg);
    }
    let [uri, name] = position.as_slice() else {
        return Err("usage: libvirt-shutdown URI GUEST [--timeout SECONDS]".into());
    };
    let milliseconds = timeout
        .checked_mul(1000)
        .and_then(|v| i32::try_from(v).ok())
        .filter(|v| *v > 0)
        .ok_or("shutdown timeout must be positive and representable")?;
    native::shutdown(uri, name, milliseconds)
}
#[cfg(not(target_os = "linux"))]
fn run() -> Result<(), Box<dyn std::error::Error>> {
    Err("libvirt shutdown is supported on Linux only".into())
}
fn main() -> std::process::ExitCode {
    match run() {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(error) => {
            eprintln!(
                "Guest shutdown failed or did not complete before the deadline; guest was not forcibly stopped: {error}"
            );
            std::process::ExitCode::FAILURE
        }
    }
}
