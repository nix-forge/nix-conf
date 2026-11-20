//! Reconcile mutable Spotify preferences without disturbing unmanaged records.
use std::{
    collections::{BTreeMap, BTreeSet},
    env, fs,
    io::{self, Write},
    path::Path,
    process::{Command, ExitCode},
};

fn update(managed: &[u8], existing: &[u8]) -> Vec<u8> {
    let mut order = Vec::new();
    let mut values = BTreeMap::new();
    for record in managed
        .split_inclusive(|b| *b == b'\n')
        .map(|line| line.strip_suffix(b"\n").unwrap_or(line))
    {
        let split = record
            .iter()
            .position(|b| *b == b'=')
            .unwrap_or(record.len());
        let key = &record[..split];
        order.push(key);
        values.insert(key, record.get(split + 1..).unwrap_or_default());
    }
    let mut found = BTreeSet::new();
    let mut out = Vec::new();
    for record in existing
        .split_inclusive(|b| *b == b'\n')
        .map(|line| line.strip_suffix(b"\n").unwrap_or(line))
    {
        if let Some(split) = record.iter().position(|b| *b == b'=')
            && let Some(value) = values.get(&record[..split])
        {
            if found.insert(&record[..split]) {
                append(&mut out, &record[..split], value);
            }
            continue;
        }
        out.extend_from_slice(record);
        out.push(b'\n');
    }
    for key in order {
        if !found.contains(key) {
            append(&mut out, key, values[key]);
        }
    }
    out
}
fn append(out: &mut Vec<u8>, key: &[u8], value: &[u8]) {
    out.extend_from_slice(key);
    out.push(b'=');
    out.extend_from_slice(value);
    out.push(b'\n');
}
fn reconcile(managed: &[u8], path: &Path) -> io::Result<()> {
    if !path.is_file() {
        return Ok(());
    }
    let old = fs::read(path)?;
    let new = update(managed, &old);
    if new == old {
        return Ok(());
    }
    let parent = path
        .parent()
        .ok_or_else(|| io::Error::other("preference file has no parent"))?;
    let mut temporary = tempfile::NamedTempFile::new_in(parent)?;
    temporary.write_all(&new)?;
    temporary.as_file().sync_all()?;
    temporary.persist(path).map_err(|e| e.error)?;
    Ok(())
}
fn run() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<_> = env::args_os().skip(1).collect();
    if args.len() != 3 {
        return Err("usage: spotify-preferences MANAGED PREFERENCES_ROOT PGREP".into());
    }
    for name in ["Spotify", "spotify"] {
        let status = Command::new(&args[2]).args(["-x", name]).status()?;
        match status.code() {
            Some(0) => {
                println!("Skipping Spotify preferences because Spotify is running.");
                return Ok(());
            }
            Some(1) => (),
            _ => return Err("could not determine whether Spotify is running".into()),
        }
    }
    let managed = fs::read(&args[0])?;
    let root = Path::new(&args[1]);
    reconcile(&managed, &root.join("prefs"))?;
    match fs::read_dir(root.join("Users")) {
        Ok(entries) => {
            for entry in entries {
                let entry = entry?;
                if entry.file_name().as_encoded_bytes().ends_with(b"-user") {
                    reconcile(&managed, &entry.path().join("prefs"))?;
                }
            }
        }
        Err(e) if e.kind() == io::ErrorKind::NotFound => (),
        Err(e) => return Err(e.into()),
    }
    Ok(())
}
fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("spotify-preferences: {e}");
            ExitCode::FAILURE
        }
    }
}
