mod cli;
mod manifest;
mod policy;
mod resources;
use resources::Command;
mod windows;
mod workstation;
use std::{
    fs,
    io::{self, Read, Write},
    os::unix::{fs::PermissionsExt, process::ExitStatusExt},
    path::Path,
    process::Stdio,
};
#[derive(Debug)]
struct CommandFailure(std::process::ExitStatus);
impl std::fmt::Display for CommandFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "native command failed ({})", self.0)
    }
}
impl std::error::Error for CommandFailure {}
fn command_status(status: std::process::ExitStatus) -> Result {
    if status.success() {
        Ok(())
    } else {
        Err(Box::new(CommandFailure(status)))
    }
}
type Result<T = ()> = std::result::Result<T, Box<dyn std::error::Error>>;
fn ensure(ok: bool, message: impl Into<String>) -> Result {
    if ok {
        Ok(())
    } else {
        Err(message.into().into())
    }
}
fn command(tool: &str, args: &[&str]) -> Command {
    let mut c = Command::new(tool);
    c.args(args)
        .env("LC_ALL", "C")
        .env_remove("LIBVIRT_DEFAULT_URI")
        .env_remove("VIRSH_DEFAULT_CONNECT_URI");
    c
}
fn output(tool: &str, args: &[&str]) -> Result<String> {
    let o = command(tool, args).stderr(Stdio::null()).output()?;
    command_status(o.status)?;
    Ok(String::from_utf8(o.stdout)?.trim_end_matches('\n').into())
}
fn run(tool: &str, args: &[&str]) -> Result {
    let status = command(tool, args).status()?;
    command_status(status)
}
fn run_controller(tool: &str, args: &[&str]) -> Result {
    command_status(command(tool, args).cooperative().status()?)
}
fn pipe_controller(tool: &str, args: &[&str], input: &[u8]) -> Result<String> {
    let output = command(tool, args)
        .cooperative()
        .output_with_input(Some(input))?;
    command_status(output.status)?;
    Ok(String::from_utf8(output.stdout)?
        .trim_end_matches('\n')
        .into())
}
fn exec(tool: &str, args: &[&str]) -> Result {
    Err(command(tool, args).exec().into())
}
fn pipe(tool: &str, args: &[&str], input: &[u8]) -> Result<String> {
    let o = command(tool, args).output_with_input(Some(input))?;
    command_status(o.status)?;
    Ok(String::from_utf8(o.stdout)?.trim_end_matches('\n').into())
}
fn regular(path: &str) -> bool {
    fs::symlink_metadata(path).is_ok_and(|m| m.is_file())
}
fn exists(path: &str) -> bool {
    fs::symlink_metadata(path).is_ok()
}
fn mode(path: &str, bits: u32) -> Result {
    fs::set_permissions(path, fs::Permissions::from_mode(bits))?;
    Ok(())
}
fn atomic(path: &str, data: &[u8], bits: u32) -> Result {
    let parent = Path::new(path).parent().ok_or("missing parent")?;
    fs::create_dir_all(parent)?;
    let (mut f, _cleanup) = resources::temporary(Some(parent))?;
    f.as_file()
        .set_permissions(fs::Permissions::from_mode(bits))?;
    f.write_all(data)?;
    f.persist(path)?;
    Ok(())
}
fn one_line() -> Result<String> {
    let mut s = String::new();
    io::stdin().read_to_string(&mut s)?;
    ensure(
        s.ends_with('\n') && s.lines().count() == 1,
        "input must contain exactly one line",
    )?;
    s.pop();
    Ok(s)
}
fn main() {
    if let Err(e) = main_result() {
        eprintln!("error: {e}");
        std::process::exit(
            e.downcast_ref::<CommandFailure>()
                .and_then(|e| {
                    e.0.code()
                        .or_else(|| e.0.signal().map(|signal| 128 + signal))
                })
                .unwrap_or(1),
        )
    }
}
fn main_result() -> Result {
    resources::signals()?;
    let a: Vec<String> = std::env::args().skip(1).collect();
    if a.len() < 2 {
        eprintln!("usage: libvirt-control <mode> <policy.json> [arguments ...]");
        std::process::exit(64)
    };
    let policy_json = fs::read(&a[1])?;
    let args = &a[2..];
    match a[0].as_str() {
        "setup" => workstation::setup(&serde_json::from_slice(&policy_json)?),
        "profile-guard" => workstation::guard(&serde_json::from_slice(&policy_json)?, args),
        "sleep-hook" => workstation::sleep_hook(&serde_json::from_slice(&policy_json)?, args),
        "control" => workstation::control(&serde_json::from_slice(&policy_json)?, args),
        "reconcile" => windows::reconcile(&serde_json::from_slice(&policy_json)?),
        "windows-control" => {
            rustix::process::umask(rustix::fs::Mode::from_raw_mode(0o077));
            windows::control(&serde_json::from_slice(&policy_json)?, args)
        }
        "vm" => cli::vm(&serde_json::from_slice(&policy_json)?, args),
        "windows-vm" => cli::windows(&serde_json::from_slice(&policy_json)?, args),
        "wizard" => cli::wizard(&serde_json::from_slice(&policy_json)?),
        _ => Err("unknown mode".into()),
    }
}
fn usage(message: &str) -> ! {
    eprintln!("usage: {message}");
    std::process::exit(64)
}
