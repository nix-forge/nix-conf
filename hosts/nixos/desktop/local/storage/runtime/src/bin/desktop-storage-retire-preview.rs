//! Retire only byte-identical recorded overrides, preserving operator changes.
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::{fs, os::unix::fs::symlink, path::Path};
type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
fn field<'a>(entry: &'a Value, key: &str) -> Result<&'a str> {
    entry[key]
        .as_str()
        .ok_or_else(|| format!("missing {key}").into())
}
fn link_matches(path: &Path, value: &Value) -> bool {
    value
        .as_str()
        .is_some_and(|v| fs::read_link(path).is_ok_and(|p| p == Path::new(v)))
}
fn retire_entry(entry: &Value) -> Result<bool> {
    let path = Path::new(field(entry, "path")?);
    if !path.exists() && !path.is_symlink() {
        return Ok(true);
    }
    if entry.get("symlink").is_some() {
        if link_matches(path, &entry["symlink"]) {
            fs::remove_file(path)?;
            return Ok(true);
        }
        return Ok(link_matches(path, &entry["adoptedLink"]));
    }
    if link_matches(path, &entry["restoreLink"]) {
        return Ok(true);
    }
    if path.is_symlink()
        || !path.is_file()
        || format!("{:x}", Sha256::digest(fs::read(path)?)) != field(entry, "sha256")?
    {
        return Ok(false);
    }
    fs::remove_file(path)?;
    if let Some(link) = entry.get("restoreLink") {
        symlink(link.as_str().ok_or("invalid restoreLink")?, path)?;
    }
    Ok(true)
}
fn retire(manifest: &Path) -> Result<()> {
    if !manifest.exists() {
        return Ok(());
    }
    let record: Value = serde_json::from_slice(&fs::read(manifest)?)?;
    let mut changed = false;
    for entry in record["overrides"].as_array().ok_or("missing overrides")? {
        if !retire_entry(entry)? {
            changed = true;
        }
    }
    if changed {
        eprintln!("Storage preview has operator changes; retaining its recovery pin and manifest");
        return Ok(());
    }
    let pin = Path::new(field(&record, "pin")?);
    if link_matches(pin, &record["target"]) {
        fs::remove_file(pin)?;
    } else if pin.exists() || pin.is_symlink() {
        eprintln!("Storage preview pin changed; preserving it");
        return Ok(());
    }
    fs::rename(manifest, manifest.with_extension("retired.json"))?;
    Ok(())
}
fn main() {
    if let Err(error) = retire(Path::new("/var/lib/desktop-storage/preview-manifest.json")) {
        eprintln!("Storage preview retirement failed: {error}");
        std::process::exit(1);
    }
}
