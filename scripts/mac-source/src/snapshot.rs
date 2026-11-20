//! Capture and verify a source tree with a stable manifest identity.

use crate::{Result, capture, fail, string, strings, text};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    collections::BTreeMap,
    fs,
    os::unix::fs::{DirBuilderExt, PermissionsExt, symlink},
    path::{Path, PathBuf},
    process::{Command, Stdio},
};

const MANIFEST: &str = ".mac-source-manifest.json";

// Python's historical canonical encoding uses ensure_ascii=True, including surrogate
// pairs. Keep the exact wire identity so old manifests and receipts remain valid.
pub(super) fn encoded(v: &Value) -> Result<Vec<u8>> {
    let raw = serde_json::to_string(v)?;
    let mut s = String::new();
    for c in raw.chars() {
        if c.is_ascii() && c != '\u{7f}' {
            s.push(c);
        } else {
            let mut b = [0; 2];
            for u in c.encode_utf16(&mut b) {
                s.push_str(&format!("\\u{u:04x}"));
            }
        }
    }
    Ok(s.into_bytes())
}
fn hash(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}
fn digest(v: &Value) -> Result<String> {
    Ok(hash(&encoded(v)?))
}
fn relative(name: &str) -> Result<PathBuf> {
    if name.is_empty()
        || name.starts_with('/')
        || name == MANIFEST
        || name
            .split('/')
            .any(|p| p.is_empty() || p == "." || p == ".." || p == ".git")
    {
        return fail(format!("Unsafe export path: {name:?}"));
    }
    Ok(name.into())
}
fn normalize(path: &Path) -> PathBuf {
    let mut out = PathBuf::new();
    for c in path.components() {
        match c {
            std::path::Component::CurDir => {}
            std::path::Component::ParentDir => {
                if out.file_name().is_some_and(|n| n != "..") {
                    out.pop();
                } else {
                    out.push("..");
                }
            }
            _ => out.push(c),
        }
    }
    out
}
fn record(root: &Path, name: &str) -> Result<Value> {
    let rel = relative(name)?;
    let path = root.join(&rel);
    let mut parent = rel.parent();
    while let Some(p) = parent {
        if root.join(p).symlink_metadata()?.file_type().is_symlink() {
            return fail(format!("Source parent is a symlink: {name}"));
        }
        parent = p.parent();
    }
    let info = fs::symlink_metadata(&path)?;
    if info.file_type().is_symlink() {
        let target = fs::read_link(&path)?;
        let normalized = normalize(&rel.parent().unwrap_or(Path::new("")).join(&target));
        if target.is_absolute() || normalized.starts_with("..") {
            return fail(format!("Symlink escapes the snapshot: {name}"));
        }
        return Ok(json!({"kind":"link","target":target.to_str().ok_or("Non UTF-8 link")?}));
    }
    if !info.is_file() {
        return fail(format!("Unsupported source entry: {name}"));
    }
    Ok(
        json!({"kind":"file","executable":info.permissions().mode() & 0o111 != 0,"sha256":hash(&fs::read(path)?)}),
    )
}
fn visit(
    root: &Path,
    prefix: &str,
    files: &mut BTreeMap<String, Value>,
    repos: &mut BTreeMap<String, Value>,
) -> Result<()> {
    let repo = root.join(prefix);
    if !repo.join(".git").exists() {
        return fail(format!("Submodule is not initialized: {prefix}"));
    }
    let index = capture(&["git", "ls-files", "--stage", "-z"], Some(&repo))?;
    repos.insert(
        prefix.into(),
        json!({"head":text(&["git","rev-parse","HEAD"],Some(&repo))?,"indexSha256":hash(&index)}),
    );
    for entry in index.split(|b| *b == 0).filter(|e| !e.is_empty()) {
        let (meta, raw) = entry.split_at(
            entry
                .iter()
                .position(|b| *b == b'\t')
                .ok_or("Malformed Git index")?,
        );
        let fields = std::str::from_utf8(meta)?
            .split_whitespace()
            .collect::<Vec<_>>();
        if fields.len() != 3 || fields[2] != "0" {
            return fail(format!("Resolve index conflicts before export: {prefix}"));
        }
        let local = std::str::from_utf8(&raw[1..])?;
        relative(local)?;
        let name = if prefix == "." {
            local.to_string()
        } else {
            format!("{prefix}/{local}")
        };
        if fields[0] == "160000" {
            visit(root, &name, files, repos)?;
        } else if fs::symlink_metadata(root.join(&name)).is_ok() {
            files.insert(name.clone(), record(root, &name)?);
        }
    }
    Ok(())
}
fn working_tree(root: &Path, includes: &[String]) -> Result<Value> {
    let mut files = BTreeMap::new();
    let mut repos = BTreeMap::new();
    visit(root, ".", &mut files, &mut repos)?;
    for name in includes {
        relative(name)?;
        let owner = repos
            .keys()
            .filter(|p| p.as_str() == "." || name.starts_with(&format!("{p}/")))
            .max_by_key(|p| p.len())
            .ok_or("No source owner")?;
        let local = if owner == "." {
            name.as_str()
        } else {
            name.strip_prefix(&format!("{owner}/"))
                .ok_or("Invalid owner")?
        };
        let s = Command::new("git")
            .args(["check-ignore", "--no-index", "--", local])
            .current_dir(root.join(owner))
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()?;
        if s.code() != Some(1) {
            return fail(format!("Ignored or invalid explicit source: {name}"));
        }
        files.insert(name.clone(), record(root, name)?);
    }
    Ok(json!({"schema":1,"repositories":repos,"files":files}))
}
fn walk(root: &Path, base: &Path, files: &mut BTreeMap<String, Value>) -> Result<()> {
    for e in fs::read_dir(base)? {
        let e = e?;
        let p = e.path();
        if e.file_type()?.is_dir() {
            walk(root, &p, files)?;
        } else {
            let name = p
                .strip_prefix(root)?
                .to_str()
                .ok_or("Non UTF-8 source path")?
                .to_string();
            if name != MANIFEST {
                files.insert(name.clone(), record(root, &name)?);
            }
        }
    }
    Ok(())
}
fn tree_files(root: &Path) -> Result<Value> {
    let mut files = BTreeMap::new();
    walk(root, root, &mut files)?;
    Ok(serde_json::to_value(files)?)
}
fn mismatch(a: &Value, b: &Value) -> Result<()> {
    let a = a.as_object().ok_or("Invalid file manifest")?;
    let b = b.as_object().ok_or("Invalid file map")?;
    let mut keys = a
        .keys()
        .chain(b.keys())
        .filter(|k| a.get(*k) != b.get(*k))
        .cloned()
        .collect::<Vec<_>>();
    keys.sort();
    keys.dedup();
    if !keys.is_empty() {
        return fail(format!(
            "Source mismatch (missing, extra, content, mode or symlink): {}",
            keys.into_iter().take(20).collect::<Vec<_>>().join(", ")
        ));
    }
    Ok(())
}
pub(super) fn snapshot(root: &Path, dest: &Path, includes: &[String]) -> Result<String> {
    let before = working_tree(root, includes)?;
    fs::DirBuilder::new().mode(0o700).create(dest)?;
    for (name, item) in before["files"].as_object().ok_or("Invalid files")? {
        let path = dest.join(relative(name)?);
        fs::create_dir_all(path.parent().ok_or("Missing parent")?)?;
        if item["kind"] == "link" {
            symlink(string(item, "target")?, path)?;
        } else {
            fs::copy(root.join(name), &path)?;
            fs::set_permissions(
                path,
                fs::Permissions::from_mode(if item["executable"] == true {
                    0o755
                } else {
                    0o644
                }),
            )?;
        }
    }
    mismatch(&before["files"], &tree_files(dest)?)?;
    if before != working_tree(root, includes)? {
        return fail("Working tree changed during export; retry after the writer finishes");
    }
    let identity = digest(&before)?;
    let mut bytes = encoded(&before)?;
    bytes.push(b'\n');
    fs::write(dest.join(MANIFEST), bytes)?;
    Ok(identity)
}
pub(super) fn verify(root: &Path, expected: &str) -> Result<Value> {
    if fs::symlink_metadata(root)?.file_type().is_symlink()
        || !root.is_dir()
        || fs::symlink_metadata(root.join(MANIFEST))?
            .file_type()
            .is_symlink()
    {
        return fail("Require a real snapshot directory and manifest");
    }
    let v: Value = serde_json::from_slice(&fs::read(root.join(MANIFEST))?)?;
    if v["schema"] != 1 || digest(&v)? != expected {
        return fail("Snapshot manifest does not match the expected export identity");
    }
    mismatch(&v["files"], &tree_files(root)?)?;
    Ok(v)
}
pub(super) fn freshness(v: &Value) -> Result<()> {
    let current = working_tree(Path::new(string(v, "source")?), &strings(&v["includes"])?)?;
    if digest(&current)? != string(v, "identity")? {
        return fail(
            "Local source changed since export; create a new Mac export before running commands",
        );
    }
    Ok(())
}
