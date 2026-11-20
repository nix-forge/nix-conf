//! Execute owner-authorized workspace commands from protected runtime data.
use rustix::fs::{Mode, OFlags};
use serde_json::Value;
use std::{
    error::Error,
    fs::File,
    os::unix::{fs::MetadataExt, process::CommandExt},
    path::Path,
    process::Command,
};
type Result<T> = std::result::Result<T, Box<dyn Error>>;
fn required<'a>(value: &'a Value, name: &str) -> Result<&'a str> {
    value
        .get(name)
        .and_then(Value::as_str)
        .ok_or_else(|| format!("missing workspace field: {name}").into())
}
fn run() -> Result<()> {
    let args: Vec<_> = std::env::args_os().skip(1).collect();
    let (path, args) = args
        .split_first()
        .ok_or("a private configuration path is required")?;
    if !Path::new(path).is_absolute() {
        return Err("private configuration path must be absolute".into());
    }
    let file = File::from(rustix::fs::open(
        Path::new(path),
        OFlags::RDONLY | OFlags::NOFOLLOW | OFlags::CLOEXEC,
        Mode::empty(),
    )?);
    let metadata = file.metadata()?;
    if !metadata.is_file()
        || metadata.uid() != rustix::process::getuid().as_raw()
        || metadata.mode() & 0o7777 != 0o600
        || metadata.nlink() != 1
    {
        return Err("workspace configuration must be an owner-only regular file".into());
    }
    let config: Value = serde_json::from_reader(file)?;
    let action = args.first().and_then(|a| a.to_str()).unwrap_or("status");
    let command = match action {
        "service" | "health" => {
            if args.len() != 2 {
                return Err("a service name is required".into());
            }
            config
                .get(action)
                .and_then(|v| args[1].to_str().and_then(|s| v.get(s)))
        }
        "backup-job" => config.get("backup_job"),
        _ => config.get("cli"),
    }
    .and_then(Value::as_array)
    .ok_or("missing workspace command")?;
    let command = command
        .iter()
        .map(|v| {
            v.as_str()
                .ok_or("workspace command arguments must be strings")
        })
        .collect::<std::result::Result<Vec<_>, _>>()?;
    let (executable, command_args) = command
        .split_first()
        .ok_or("workspace command must not be empty")?;
    if !Path::new(executable).is_absolute() {
        return Err("workspace commands require an absolute executable".into());
    }
    let mut process = Command::new(executable);
    process.args(command_args);
    if !matches!(action, "service" | "health" | "backup-job") {
        process.args(args);
    }
    process
        .env("WORKSPACE_STATE_DIR", required(&config, "state_directory")?)
        .env(
            "WORKSPACE_SOURCE_DIR",
            required(&config, "source_directory")?,
        )
        .current_dir(required(&config, "source_directory")?);
    Err(process.exec().into())
}
fn main() -> std::process::ExitCode {
    // Private command values and parser excerpts must never enter diagnostics.
    match run() {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(_) => {
            eprintln!("Unable to dispatch the protected workspace command");
            std::process::ExitCode::FAILURE
        }
    }
}
