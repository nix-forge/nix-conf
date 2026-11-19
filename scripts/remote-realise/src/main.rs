//! Realize one exact native derivation, keeping compilation and roots remote.
use serde_json::Value;
use std::error::Error;
use std::os::unix::process::ExitStatusExt;
use std::path::{Component, Path};
use std::process::{Command, ExitCode, ExitStatus};

type Result<T> = std::result::Result<T, Box<dyn Error>>;
fn code(status: ExitStatus) -> i32 {
    status
        .code()
        .unwrap_or_else(|| 128 + status.signal().unwrap_or(1))
}
fn capture(command: &mut Command) -> Result<String> {
    let output = command.stderr(std::process::Stdio::inherit()).output()?;
    if !output.status.success() {
        return Err("Command failed; see command diagnostics".into());
    }
    Ok(String::from_utf8(output.stdout)?)
}
fn run(command: &mut Command) -> Result<()> {
    if !command.status()?.success() {
        return Err("Command failed".into());
    }
    Ok(())
}
fn quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\"'\"'"))
}
fn remote(host: &str, args: &[&str]) -> Command {
    let mut command = Command::new("ssh");
    command.args(["-o", "BatchMode=yes", "-o", "ConnectTimeout=10", host]);
    command.arg(args.iter().map(|s| quote(s)).collect::<Vec<_>>().join(" "));
    command
}
fn store_path(value: &str) -> bool {
    Path::new(value).parent() == Some(Path::new("/nix/store")) && !value.ends_with('/')
}
fn record<'a>(document: &'a Value, derivation: &str) -> Result<&'a Value> {
    let envelope = document
        .as_object()
        .ok_or("Derivation metadata must be an object")?;
    let (records, key) = if let Some(version) = envelope.get("version") {
        if envelope.len() != 2 || !matches!(version.as_u64(), Some(2 | 4)) {
            return Err("Unsupported derivation metadata envelope".into());
        }
        (
            envelope
                .get("derivations")
                .and_then(Value::as_object)
                .ok_or("Invalid derivation records")?,
            Path::new(derivation)
                .file_name()
                .and_then(|s| s.to_str())
                .ok_or("Invalid derivation")?,
        )
    } else {
        (envelope, derivation)
    };
    if records.len() != 1 {
        return Err("Require exactly the requested derivation".into());
    }
    let record = records
        .get(key)
        .filter(|v| v.is_object())
        .ok_or("Require exactly the requested derivation")?;
    if record.get("system").and_then(Value::as_str).is_none() {
        return Err("Derivation has no valid build system".into());
    }
    if let Some(name) = record
        .get("name")
        .or_else(|| record.get("env").and_then(|env| env.get("name")))
        && !name.is_null()
        && !name.is_string()
    {
        return Err("Derivation has no valid name".into());
    }
    Ok(record)
}
fn main_result() -> Result<i32> {
    let mut positional = Vec::new();
    let mut protected = Vec::new();
    let mut cores = 8u8;
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "-h" | "--help" => {
                println!(
                    "usage: remote-realise host derivation result_root [--cores CORES] [--protected-system NAME]"
                );
                return Ok(0);
            }
            "--cores" => cores = args.next().ok_or("Missing cores")?.parse()?,
            "--protected-system" => protected.push(args.next().ok_or("Missing protected system")?),
            _ if arg.starts_with("--cores=") => cores = arg[8..].parse()?,
            _ if arg.starts_with("--protected-system=") => protected.push(arg[19..].to_string()),
            _ if arg.starts_with('-') => return Err("Unrecognized argument".into()),
            _ => positional.push(arg),
        }
    }
    let [host, derivation, root] = positional.as_slice() else {
        return Err("Require host, derivation and result_root".into());
    };
    if host.is_empty()
        || host.starts_with('-')
        || !host
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"_@.-".contains(&b))
    {
        return Err("Require a hostname or SSH alias".into());
    }
    if !store_path(derivation) || Path::new(derivation).extension().is_none_or(|s| s != "drv") {
        return Err("Require a Nix store derivation".into());
    }
    let root_path = Path::new(root);
    if !root_path.is_absolute()
        || root_path
            .components()
            .any(|c| matches!(c, Component::ParentDir))
        || root_path.file_name().is_none()
    {
        return Err("Require an absolute remote result root".into());
    }
    if !(1..=16).contains(&cores) {
        return Err("Require 1-16 compiler jobs".into());
    }
    let native = capture(&mut remote(
        host,
        &[
            "nix",
            "eval",
            "--impure",
            "--raw",
            "--expr",
            "builtins.currentSystem",
        ],
    ))?;
    let native = native.trim();
    if ![
        "x86_64-linux",
        "aarch64-linux",
        "x86_64-darwin",
        "aarch64-darwin",
    ]
    .contains(&native)
    {
        return Err("Unsupported native remote platform".into());
    }
    let document: Value = serde_json::from_str(&capture(Command::new("nix").args([
        "derivation",
        "show",
        derivation,
    ]))?)?;
    let record = record(&document, derivation)?;
    if record["system"] != native {
        return Err("Derivation platform must match the native remote host".into());
    }
    let name = record
        .get("name")
        .filter(|v| !v.is_null())
        .or_else(|| record.get("env").and_then(|v| v.get("name")))
        .and_then(Value::as_str)
        .unwrap_or("");
    if protected
        .iter()
        .any(|p| name.starts_with(&format!("nixos-system-{p}-")))
    {
        return Err("Use the dedicated system-build recipe for this protected closure".into());
    }
    run(Command::new("nix").args([
        "copy",
        "--derivation",
        "--to",
        &format!("ssh://{host}"),
        derivation,
    ]))?;
    let parent = root_path
        .parent()
        .and_then(|p| p.to_str())
        .ok_or("Invalid root parent")?;
    run(&mut remote(host, &["mkdir", "-p", "--", parent]))?;
    let status = remote(
        host,
        &[
            "nix-store",
            "--realise",
            derivation,
            "--add-root",
            root,
            "--indirect",
            "--builders",
            "",
            "--max-jobs",
            "1",
            "--cores",
            &cores.to_string(),
            "--option",
            "extra-platforms",
            "",
        ],
    )
    .stdout(std::process::Stdio::null())
    .status()?;
    if !status.success() {
        return Ok(code(status));
    }
    let outputs = capture(&mut remote(
        host,
        &["nix-store", "--query", "--outputs", derivation],
    ))?;
    let outputs: Vec<_> = outputs.lines().collect();
    if outputs.is_empty() || outputs.iter().any(|s| !store_path(s)) {
        return Err("Remote output query did not return store paths".into());
    }
    for output in outputs {
        println!("{output}");
    }
    Ok(0)
}
fn main() -> ExitCode {
    match main_result() {
        Ok(status) => ExitCode::from(status as u8),
        Err(error) => {
            eprintln!("remote-realise: {error}");
            ExitCode::from(2)
        }
    }
}
