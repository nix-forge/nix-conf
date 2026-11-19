//! Git-backed source identity and canonical fingerprints.

use crate::{R, fail, output, require, text};
use serde_json::{Value as V, json};
use sha2::{Digest, Sha256};
use std::{
    collections::BTreeMap,
    fs,
    os::unix::{ffi::OsStrExt, fs::PermissionsExt},
    path::{Path, PathBuf},
};

pub(super) fn hash(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}
// Preserve Python's canonical JSON fingerprints, including ASCII escapes and spaces.
fn canonical(v: &V) -> String {
    match v {
        V::Array(a) => format!(
            "[{}]",
            a.iter().map(canonical).collect::<Vec<_>>().join(", ")
        ),
        V::Object(o) => format!(
            "{{{}}}",
            o.iter()
                .map(|(k, v)| format!("{}: {}", canonical(&json!(k)), canonical(v)))
                .collect::<Vec<_>>()
                .join(", ")
        ),
        V::String(s) => {
            let mut r = String::from("\"");
            for c in s.chars() {
                match c {
                    '"' => r.push_str("\\\""),
                    '\\' => r.push_str("\\\\"),
                    '\n' => r.push_str("\\n"),
                    '\r' => r.push_str("\\r"),
                    '\t' => r.push_str("\\t"),
                    '\u{8}' => r.push_str("\\b"),
                    '\u{c}' => r.push_str("\\f"),
                    c if !(' '..='~').contains(&c) => {
                        let mut buf = [0; 2];
                        for u in c.encode_utf16(&mut buf) {
                            r.push_str(&format!("\\u{u:04x}"));
                        }
                    }
                    c => r.push(c),
                }
            }
            r.push('"');
            r
        }
        _ => v.to_string(),
    }
}
pub(super) fn fingerprint(v: &V) -> String {
    hash(canonical(v).as_bytes())
}

fn git(root: &Path, args: &[&str]) -> R<Vec<u8>> {
    output(root, "git", args, true)
}

pub(super) fn root(path: &Path) -> R<PathBuf> {
    let p = path.canonicalize()?;
    let top = PathBuf::from(String::from_utf8(git(&p, &["rev-parse", "--show-toplevel"])?)?.trim())
        .canonicalize()?;
    require(
        p == top,
        "Use the Git repository root as --source so all flake inputs are fingerprinted",
    )?;
    Ok(p)
}
pub(super) fn source(path: &Path) -> R<V> {
    let p = root(path)?;
    let mut entries = Vec::new();
    let mut locks = BTreeMap::new();
    let mut subs = BTreeMap::new();
    for row in git(&p, &["ls-files", "--stage", "-z"])?
        .split(|b| *b == 0)
        .filter(|r| !r.is_empty())
    {
        let tab = row
            .iter()
            .position(|b| *b == b'\t')
            .ok_or("invalid Git index")?;
        let meta = std::str::from_utf8(&row[..tab])?
            .split_whitespace()
            .collect::<Vec<_>>();
        require(
            meta.len() == 3 && meta[2] == "0",
            "Resolve merge conflicts before recording source evidence",
        )?;
        // Git filenames need not be UTF-8; rejecting them is safer than silently aliasing bytes.
        let name = std::str::from_utf8(&row[tab + 1..])?;
        let file = p.join(name);
        if meta[0] == "160000" {
            require(
                file.join(".git").exists(),
                &format!("Initialize the {name} submodule before validation"),
            )?;
            let sub = source(&file)?;
            entries.push(json!([name, "160000", sub["tree_sha256"]]));
            subs.insert(name.to_owned(), sub);
            continue;
        }
        let m = match fs::symlink_metadata(&file) {
            Ok(m) => m,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => continue,
            Err(e) => return Err(e.into()),
        };
        if m.file_type().is_symlink() {
            entries.push(json!([
                name,
                "120000",
                hash(fs::read_link(file)?.as_os_str().as_bytes())
            ]));
        } else if m.is_file() {
            let d = hash(&fs::read(&file)?);
            let mode = if m.permissions().mode() & 0o111 != 0 {
                "100755"
            } else {
                "100644"
            };
            entries.push(json!([name, mode, d]));
            if file.file_name().is_some_and(|x| x == "flake.lock") {
                locks.insert(name.to_owned(), d);
            }
        } else {
            return fail("Unsupported tracked file kind");
        }
    }
    entries.sort_by(|a, b| text(&a[0]).as_bytes().cmp(text(&b[0]).as_bytes()));
    Ok(
        json!({"revision":String::from_utf8(git(&p,&["rev-parse","HEAD"])?)?.trim(),"tree_sha256":fingerprint(&json!(entries)),"dirty":!git(&p,&["status","--porcelain","--untracked-files=no","--ignore-submodules=untracked"])?.is_empty(),"lockfiles":locks,"submodules":subs}),
    )
}
