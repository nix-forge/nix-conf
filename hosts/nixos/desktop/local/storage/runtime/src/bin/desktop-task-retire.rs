use desktop_storage_runtime::*;
use serde_json::json;
use std::{
    fs,
    os::unix::fs::{MetadataExt, PermissionsExt},
    path::{Path, PathBuf},
};
fn location(root: &Path, owner: &str, data_mount: &str) -> Result<(PathBuf, PathBuf)> {
    if !regex::Regex::new(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$")?.is_match(owner) {
        return fail("Unsafe cache owner");
    }
    let m = fs::metadata(root)?;
    if root.is_symlink() || m.uid() != 0 || m.ino() != 256 {
        return fail("Task cache root is not the provisioned subvolume");
    }
    let mount = |p: &str| -> Result<serde_json::Value> {
        Ok(serde_json::from_str::<serde_json::Value>(&cmd(&[
            "findmnt",
            "--json",
            "--target",
            p,
            "--output",
            "UUID,TARGET",
        ])?)?["filesystems"][0]
            .clone())
    };
    let data = mount(data_mount)?;
    let cache = mount(&root.to_string_lossy())?;
    if data["target"] != data_mount || s(&data["uuid"]).is_empty() || data["uuid"] != cache["uuid"]
    {
        return fail("Task cache data mount is unavailable");
    }
    let uid = rustix::process::getuid().as_raw();
    let passwd = fs::read_to_string("/etc/passwd")?;
    let name = passwd
        .lines()
        .find_map(|l| {
            let f: Vec<_> = l.split(':').collect();
            (f.len() > 2 && f[2].parse::<u32>().ok() == Some(uid)).then(|| f[0].to_string())
        })
        .ok_or("Unknown user")?;
    let ns = root.join(name);
    if ns.is_symlink() || fs::metadata(&ns)?.uid() != uid {
        return fail("Task cache namespace ownership mismatch");
    }
    let target = ns.join(owner);
    if target.is_symlink() {
        return fail("Task cache cannot be a symlink");
    }
    Ok((target, ns.join(format!("{owner}.owner.json"))))
}
fn walk(path: &Path, dirs: &mut Vec<PathBuf>) -> Result<()> {
    let m = fs::symlink_metadata(path)?;
    if m.is_symlink() {
        return Ok(());
    }
    if m.is_dir() {
        if m.uid() != rustix::process::getuid().as_raw() {
            return fail("Cache directory owned by another identity");
        }
        if !dirs.is_empty() && m.ino() == 256 {
            return fail("Nested subvolume prevents retirement");
        }
        dirs.push(path.to_owned());
        for e in fs::read_dir(path)? {
            walk(&e?.path(), dirs)?;
        }
    }
    Ok(())
}
fn main() {
    entry(|| {
        let a = args();
        let owner = option(&a, "--owner").ok_or_else(|| usage_error("--owner required"))?;
        let policy = if a.iter().any(|argument| argument == "--policy") {
            read(option(&a, "--policy").ok_or_else(|| usage_error("--policy requires a path"))?)?
        } else {
            json!({})
        };
        let data_mount = policy_path(&policy, "dataMount", LEGACY_DATA_MOUNT)?;
        let scratch_root = policy_path(&policy, "scratchRoot", "/srv/data/work/scratch")?;
        let cache_override = option(&a, "--cache-root");
        let root = Path::new(cache_override.as_deref().unwrap_or(scratch_root));
        let create = a.iter().any(|v| v == "--create-cache");
        let remove = a.iter().any(|v| v == "--remove-cache");
        let complete = a.iter().any(|v| v == "--complete-task");
        let preserved = option(&a, "--preserved-result");
        if complete != preserved.is_some()
            || create && (complete || remove)
            || !create && !(complete && remove)
        {
            return fail(
                "Choose cache creation or explicit completed removal with preserved result",
            );
        }
        let (target, marker) = location(root, &owner, data_mount)?;
        let identity = json!({"owner":owner,"uid":rustix::process::getuid().as_raw()});
        if create {
            if target.exists() {
                if read(&marker)? != identity {
                    return fail("Existing directory is not an owned cache");
                }
            } else {
                fs::create_dir(&target)?;
                fs::set_permissions(&target, fs::Permissions::from_mode(0o700))?;
                save(marker, &identity, 0o600)?;
            }
            println!("{}", target.display());
            return Ok(0);
        }
        if target.exists() {
            if read(&marker)? != identity {
                return fail("Task cache ownership mismatch");
            }
            let canonical = fs::canonicalize(&target)?;
            if fs::canonicalize(preserved.ok_or("Preserved result required")?)?
                .starts_with(&canonical)
                || fs::canonicalize(std::env::current_dir()?)?.starts_with(&canonical)
            {
                return fail("Move results and current directory outside cache");
            }
            let re = regex::Regex::new(r"\\([0-7]{3})")?;
            for line in fs::read_to_string("/proc/self/mountinfo")?.lines() {
                let mount = line
                    .split_whitespace()
                    .nth(4)
                    .ok_or("Malformed mountinfo")?;
                let mount = re.replace_all(mount, |c: &regex::Captures<'_>| {
                    u8::from_str_radix(&c[1], 8)
                        .map(char::from)
                        .unwrap_or('?')
                        .to_string()
                });
                if Path::new(mount.as_ref()).starts_with(&canonical) {
                    return fail("Nested mount prevents cache retirement");
                }
            }
            let mut dirs = Vec::new();
            walk(&target, &mut dirs)?;
            let checked = location(root, &owner, data_mount)?;
            if checked.0 != target || read(&marker)? != identity {
                return fail("Cache changed before retirement");
            }
            for dir in dirs {
                let mode = fs::symlink_metadata(&dir)?.mode();
                fs::set_permissions(dir, fs::Permissions::from_mode(mode | 0o700))?;
            }
            fs::remove_dir_all(target)?;
            fs::remove_file(marker)?;
        }
        println!("{}", json!({"owner":owner,"removed":true}));
        Ok(0)
    })
}
