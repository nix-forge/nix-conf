//! Private lifecycle state, identity records and durable transaction journals.

use fs2::FileExt;
use macos_application_tools::{Result, fail};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    fs::{self, DirBuilder, File, OpenOptions},
    io::Write,
    os::unix::fs::{DirBuilderExt, MetadataExt, OpenOptionsExt},
    path::{Path, PathBuf},
};

fn private_metadata(m: &fs::Metadata, directory: bool) -> Result<()> {
    if (if directory { m.is_dir() } else { m.is_file() })
        && m.uid() == rustix::process::getuid().as_raw()
        && m.mode() & 0o077 == 0
    {
        Ok(())
    } else {
        fail("Lifecycle state must be private, owned and real")
    }
}
pub(super) fn check_state(path: &Path) -> Result<()> {
    match fs::symlink_metadata(path) {
        Ok(m) => private_metadata(&m, true),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(e.into()),
    }
}
pub(super) fn lock(state: &Path) -> Result<File> {
    DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(state)?;
    check_state(state)?;
    let f = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .custom_flags(rustix::fs::OFlags::NOFOLLOW.bits() as i32)
        .open(state.join("lifecycle.lock"))?;
    private_metadata(&f.metadata()?, false)?;
    f.lock_exclusive()?;
    Ok(f)
}
pub(super) fn read_private(path: &Path) -> Result<Value> {
    let f = match OpenOptions::new()
        .read(true)
        .custom_flags(rustix::fs::OFlags::NOFOLLOW.bits() as i32)
        .open(path)
    {
        Ok(f) => f,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(Value::Null),
        Err(e) => return Err(e.into()),
    };
    private_metadata(&f.metadata()?, false)?;
    let v: Value = serde_json::from_reader(f)?;
    if !v.is_object() {
        return fail("Invalid application identity record");
    }
    Ok(v)
}
pub(super) fn atomic(path: &Path, bytes: &[u8], sync: bool) -> Result<()> {
    let parent = path.parent().ok_or("Missing parent")?;
    let mut f = tempfile::Builder::new()
        .prefix(".identity-")
        .tempfile_in(parent)?;
    f.write_all(bytes)?;
    f.flush()?;
    if sync {
        f.as_file().sync_all()?;
    }
    f.persist(path).map_err(|e| e.error)?;
    if sync {
        File::open(parent)?.sync_all()?;
    }
    Ok(())
}
pub(super) fn save(path: &Path, v: &Value) -> Result<()> {
    atomic(path, &serde_json::to_vec(v)?, true)
}
pub(super) fn journal(dir: &Path, status: &str, evidence: &Value) -> Result<()> {
    let mut v = evidence.clone();
    v["status"] = json!(status);
    save(&dir.join("transaction.json"), &v)
}
pub(super) fn record_path(state_directory: &Path, bundle: &str) -> PathBuf {
    state_directory.join(format!("{:x}.json", Sha256::digest(bundle.as_bytes())))
}
