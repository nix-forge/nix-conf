//! Private receipt publication and locking for source-bound operations.

use crate::{Result, fail, rustix_no_follow, snapshot::encoded};
use fs2::FileExt;
use serde_json::{Value, json};
use std::{
    fs::{self, File, OpenOptions},
    io::Write,
    os::unix::fs::{DirBuilderExt, OpenOptionsExt},
    path::Path,
    time::{SystemTime, UNIX_EPOCH},
};

pub(super) fn private_dir(path: &Path) -> Result<()> {
    fs::DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(path)?;
    if fs::symlink_metadata(path)?.file_type().is_symlink() {
        return fail("State directory is a symlink");
    }
    Ok(())
}
pub(super) fn save(path: &Path, v: &Value, exclusive: bool) -> Result<()> {
    let mut t = tempfile::NamedTempFile::new_in(path.parent().ok_or("Missing parent")?)?;
    t.write_all(&encoded(v)?)?;
    t.write_all(b"\n")?;
    t.as_file().sync_all()?;
    if exclusive {
        t.persist_noclobber(path)?;
    } else {
        t.persist(path)?;
    }
    Ok(())
}
pub(super) fn lock(path: &Path) -> Result<File> {
    let f = OpenOptions::new()
        .create(true)
        .truncate(false)
        .read(true)
        .write(true)
        .mode(0o600)
        .custom_flags(rustix_no_follow())
        .open(path)?;
    f.lock_exclusive()?;
    Ok(f)
}

pub(super) fn finish_report(path: &Path, report: &mut Value, result: &Result<i32>) -> Result<()> {
    report["finishedAt"] = json!(SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs_f64());
    match result {
        Ok(code) => {
            report["exitCode"] = json!(code);
            report["status"] = json!(if *code == 0 { "passed" } else { "failed" });
        }
        Err(e) => {
            report["status"] = json!("failed");
            report["error"] = json!(e.to_string());
        }
    }
    save(path, report, false)
}
