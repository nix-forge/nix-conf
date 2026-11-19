//! Reconcile the Dock from a Nix-generated policy, committing receipts last.
use fs2::FileExt;
use serde_json::{Value, json};
use std::{
    error::Error,
    fs::{self, OpenOptions},
    io::Write,
    os::unix::fs::{OpenOptionsExt, PermissionsExt},
    path::{Path, PathBuf},
    process::{Command, ExitCode, Stdio},
};
type Result<T> = std::result::Result<T, Box<dyn Error>>;
fn string<'a>(v: &'a Value, key: &str) -> Result<&'a str> {
    v.get(key)
        .and_then(Value::as_str)
        .ok_or_else(|| format!("missing string {key}").into())
}
fn strings(v: &Value) -> Result<Vec<String>> {
    v.as_array()
        .ok_or("expected array")?
        .iter()
        .map(|v| {
            let s = v.as_str().ok_or("expected string")?;
            if s.len() > 16384 || s.contains('\0') {
                return Err("invalid argument".into());
            }
            Ok(s.to_owned())
        })
        .collect()
}
fn execute() -> Result<()> {
    let args: Vec<_> = std::env::args_os().skip(1).collect();
    let [policy] = args.as_slice() else {
        return Err("usage: hm-dock-sync POLICY.json".into());
    };
    let data = fs::read(policy)?;
    if data.len() > 1024 * 1024 {
        return Err("policy too large".into());
    }
    let policy: Value = serde_json::from_slice(&data)?;
    let mode = string(&policy, "mode")?;
    if !matches!(mode, "authoritative" | "initialize") {
        return Err("invalid Dock mode".into());
    }
    let config_hash = string(&policy, "configHash")?;
    if config_hash.len() != 64 || !config_hash.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err("invalid configuration hash".into());
    }
    let dockutil = string(&policy, "dockutil")?;
    let cache = PathBuf::from(string(&policy, "cacheDirectory")?);
    if !Path::new(dockutil).is_absolute() || !cache.is_absolute() {
        return Err("absolute paths required".into());
    }
    let targets = strings(policy.get("targets").ok_or("missing targets")?)?;
    let actions: Vec<Vec<String>> = policy
        .get("actions")
        .and_then(Value::as_array)
        .ok_or("missing actions")?
        .iter()
        .map(strings)
        .collect::<Result<_>>()?;
    if actions.is_empty()
        || actions.len() > 4096
        || actions.iter().any(|a| a.is_empty() || a.len() > 32)
    {
        return Err("invalid action count".into());
    }
    let dry_run = std::env::var_os("DRY_RUN").is_some_and(|s| !s.is_empty());
    if dry_run {
        println!("setting up Dock items (dry run)...");
        for (i, action) in actions.iter().enumerate() {
            let mut action = action.clone();
            if i + 1 < actions.len() {
                action.push("--no-restart".into());
            }
            println!("{dockutil:?} {action:?}");
        }
        return Ok(());
    }
    fs::create_dir_all(&cache)?;
    if !cache.symlink_metadata()?.file_type().is_dir() {
        return Err("cache is not a directory".into());
    }
    fs::set_permissions(&cache, fs::Permissions::from_mode(0o700))?;
    let lock = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .open(cache.join(".sync.lock"))?;
    lock.lock_exclusive()?;
    let receipt_path = cache.join("dock-receipt.json");
    let receipt: Value = fs::read(&receipt_path)
        .ok()
        .and_then(|d| serde_json::from_slice(&d).ok())
        .unwrap_or(Value::Null);
    let current = if mode == "authoritative" {
        Some(hm_dock_state::fingerprint()?)
    } else {
        None
    };
    if receipt.get("configHash").and_then(Value::as_str) == Some(config_hash)
        && (mode == "initialize"
            || receipt.get("stateHash").and_then(Value::as_str) == current.as_deref())
    {
        println!("Dock items unchanged, skipping...");
        return Ok(());
    }
    // Every target and Dock readability must pass before --remove all.
    for target in targets {
        if !Path::new(&target).is_absolute() || !Path::new(&target).is_dir() {
            return Err(format!("Dock target unavailable: {target}").into());
        }
    }
    if !Command::new(dockutil)
        .arg("--list")
        .stdout(Stdio::null())
        .status()?
        .success()
    {
        return Err("dockutil cannot read Dock; refusing to remove items".into());
    }
    println!("setting up Dock items...");
    for (i, action) in actions.iter().enumerate() {
        let mut command = Command::new(dockutil);
        command.args(action);
        if i + 1 < actions.len() {
            command.arg("--no-restart");
        }
        if !command.status()?.success() {
            return Err("dockutil action failed; receipt unchanged".into());
        }
    }
    let state_hash = hm_dock_state::fingerprint()?;
    let mut receipt = tempfile::NamedTempFile::new_in(&cache)?;
    serde_json::to_writer(
        &mut receipt,
        &json!({"configHash": config_hash, "stateHash": state_hash}),
    )?;
    receipt.write_all(b"\n")?;
    receipt.as_file().sync_all()?;
    receipt.persist(&receipt_path)?;
    fs::File::open(&cache)?.sync_all()?;
    Ok(())
}
fn main() -> ExitCode {
    match execute() {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("hm-dock-sync: {e}");
            ExitCode::FAILURE
        }
    }
}
