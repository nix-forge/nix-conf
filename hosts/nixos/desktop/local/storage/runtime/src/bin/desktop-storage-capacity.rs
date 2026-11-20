use desktop_storage_runtime::*;
use serde_json::{Value, json};
use std::{
    fs,
    io::Write,
    os::unix::fs::{MetadataExt, PermissionsExt},
    path::Path,
};
fn probe(path: &str) -> Result<Value> {
    let target = std::path::absolute(path)?;
    let target = target.to_string_lossy();
    let mut m: Value = serde_json::from_str::<Value>(&cmd(&[
        "findmnt",
        "--nocanonicalize",
        "--json",
        "--target",
        &target,
        "--output",
        "UUID,TARGET,FSTYPE",
    ])?)?["filesystems"][0]
        .clone();
    if m["fstype"] == "autofs" {
        let layers: Value = serde_json::from_str(&cmd(&[
            "findmnt",
            "--nocanonicalize",
            "--list",
            "--json",
            "--mountpoint",
            s(&m["target"]),
            "--output",
            "UUID,TARGET,FSTYPE",
        ])?)?;
        m = layers["filesystems"]
            .as_array()
            .ok_or("Mount layers")?
            .iter()
            .rev()
            .find(|i| {
                i["target"] == m["target"] && !s(&i["fstype"]).is_empty() && i["fstype"] != "autofs"
            })
            .ok_or("Required storage is an unmounted automount")?
            .clone();
    }
    let identity = if s(&m["uuid"]).is_empty() {
        format!("device:{}", fs::metadata(target.as_ref())?.dev())
    } else {
        s(&m["uuid"]).into()
    };
    let u = rustix::fs::statvfs(target.as_ref())?;
    Ok(json!({"identity":identity,"mount":m["target"],"available":u.f_bavail*u.f_frsize}))
}
fn mounted(c: &Value) -> Result<Value> {
    let m = probe(s(&c["path"]))?;
    if c["requireMount"] != false && m["mount"] != c["path"] {
        return fail("Required storage is not mounted");
    }
    Ok(m)
}
fn cache(p: &Value) -> Result<Value> {
    let c = &p["cache"];
    mounted(&json!({"path":c["mount"]}))?;
    let root = Path::new(s(&c["root"]));
    let m = fs::metadata(root)?;
    if fs::canonicalize(root)? != root || m.ino() != 256 || m.uid() != 0 || m.mode() & 0o077 != 0 {
        return fail("Private cache subvolume is not ready");
    }
    for key in ["RESTIC_CACHE_DIR", "TMPDIR"] {
        let v = std::env::var(key)?;
        let v = Path::new(&v);
        if !v.is_absolute()
            || fs::canonicalize(v)? != v
            || !v.starts_with(root)
            || key == "TMPDIR" && !v.is_dir()
        {
            return fail("Cache environment is outside prepared subvolume");
        }
    }
    Ok(json!({"ready":true}))
}
fn status(p: &Value) -> Result<Value> {
    let previous = optional(state(p, "capacity.json"))?;
    let mut samples = json!({});
    let mut messages = Vec::new();
    for c in p["filesystems"].as_array().ok_or("Filesystems")? {
        let path = s(&c["path"]);
        match mounted(c) {
            Ok(m) => {
                let available = n(&m["available"]);
                let old = s(&previous["filesystems"][path]["severity"]);
                let level = if available < n(&c["criticalBytes"])
                    || old == "critical" && available < n(&c["criticalRecoveryBytes"])
                {
                    "critical"
                } else if available < n(&c["warningBytes"])
                    || ["warning", "critical"].contains(&old)
                        && available < n(&c["warningRecoveryBytes"])
                {
                    "warning"
                } else {
                    "healthy"
                };
                samples[path] = json!({"availableBytes":available,"severity":level});
                if level != "healthy" {
                    messages.push(format!(
                        "{} storage capacity on {path}: {} MiB available",
                        if level == "critical" {
                            "Critical"
                        } else {
                            "Warning"
                        },
                        available / 1048576
                    ));
                }
            }
            Err(_) => {
                samples[path] = json!({"severity":"unknown"});
                messages.push(format!("Storage capacity inspection failed: {path}"));
            }
        }
    }
    if let Some(caches) = p["cacheBudgets"].as_array() {
        for c in caches {
            match cmd(&[
                "du",
                "--summarize",
                "--one-file-system",
                "--block-size=1",
                s(&c["path"]),
            ]) {
                Ok(out) => {
                    if out
                        .split_whitespace()
                        .next()
                        .ok_or("du output")?
                        .parse::<u64>()?
                        > n(&c["warningBytes"])
                    {
                        messages.push("Active Restic cache exceeds its storage budget; review cache placement and repository growth".into());
                    }
                }
                Err(_) => messages.push("Regenerable cache size could not be inspected".into()),
            }
        }
    }
    let receipt = optional(state(p, "collection.json"))?;
    let age = now() - receipt["completed"].as_f64().unwrap_or(0.);
    if age < 0. || age > n(&p["collectorStaleSeconds"]) as f64 {
        messages.push("Storage collection results are missing or stale".into());
    }
    if ["failed", "unreclaimable"].contains(&s(&receipt["status"]))
        || receipt["previousFailure"]
            .as_object()
            .is_some_and(|v| !v.is_empty())
    {
        messages.push("Nix collection could not restore its capacity target; inspect rooted outputs and other writers".into());
    }
    let out = json!({"checked":now(),"filesystems":samples,"messages":messages});
    save(state(p, "capacity.json"), &out, 0o600)?;
    Ok(out)
}
fn admission(
    p: &Value,
    requests: Vec<(String, u64)>,
    recovery: bool,
    snapshot: bool,
) -> Result<Value> {
    let mut known = std::collections::BTreeMap::new();
    let mut absent = Vec::new();
    for c in p["filesystems"].as_array().ok_or("Filesystems")? {
        match mounted(c) {
            Ok(m) => {
                known.insert(s(&m["identity"]).to_owned(), (c.clone(), m));
            }
            Err(_) => {
                absent.push(s(&c["path"]).to_owned());
                absent.extend(list(&c["aliases"]));
            }
        }
    }
    let mut required = std::collections::BTreeMap::<String, u64>::new();
    for (path, amount) in requests {
        let path = Path::new(&path);
        if !path.is_absolute() || absent.iter().any(|a| path.starts_with(a)) {
            return fail("Requested storage mount is unavailable");
        }
        let path = fs::canonicalize(path)?;
        if absent.iter().any(|a| path.starts_with(a)) {
            return fail("Requested storage mount is unavailable");
        }
        let sample = probe(&path.to_string_lossy())?;
        let identity = s(&sample["identity"]);
        if !known.contains_key(identity) {
            return fail("Requested filesystem has no capacity policy");
        }
        let v = required.entry(identity.into()).or_default();
        *v = v.checked_add(amount).ok_or("Request overflow")?;
    }
    let mut results = Vec::new();
    for (identity, amount) in required {
        let (c, m) = known.get(&identity).ok_or("Policy identity")?;
        let floor = if snapshot {
            n(&c["criticalBytes"])
        } else if recovery {
            0
        } else {
            n(&c["admissionBytes"])
        };
        let available = n(&m["available"]);
        results.push(json!({"path":c["path"],"availableBytes":available,"additionalBytes":amount,"minimumRemainingBytes":floor,"admitted":available>=amount&&available-amount>=floor}));
    }
    Ok(
        json!({"checked":now(),"admitted":results.iter().all(|r|r["admitted"]==true),"recovery":recovery,"filesystems":results}),
    )
}
fn save_collection(p: &Value, r: &Value) -> Result<()> {
    save(state(p, "collection.json"), r, 0o600)?;
    let history = state(p, "collection-history.jsonl");
    if history.exists() && fs::metadata(&history)?.len() > 1048576 {
        fs::rename(&history, history.with_extension("jsonl.1"))?;
    }
    use std::os::unix::fs::OpenOptionsExt;
    let mut file = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .mode(0o600)
        .open(history)?;
    writeln!(file, "{r}")?;
    Ok(())
}
fn collect(p: &Value, force: bool) -> Result<Value> {
    let c = p["filesystems"]
        .as_array()
        .ok_or("Filesystems")?
        .iter()
        .find(|c| c["path"] == "/")
        .ok_or("Root policy")?;
    let before = n(&mounted(c)?["available"]);
    let old = optional(state(p, "collection.json"))?;
    let failure = if ["failed", "unreclaimable"].contains(&s(&old["status"])) {
        json!({"status":old["status"],"completed":old["completed"],"afterBytes":old["afterBytes"]})
    } else {
        old["previousFailure"].clone()
    };
    let mut r = json!({"started":now(),"beforeBytes":before,"status":"skipped"});
    if before < n(&p["collectBelowBytes"]) {
        if failure.is_object() {
            r["previousFailure"] = failure.clone();
            if !force
                && now() - failure["completed"].as_f64().unwrap_or(0.)
                    < n(&p["retrySeconds"]) as f64
                && before >= n(&failure["afterBytes"]).saturating_sub(n(&p["retryDropBytes"]))
            {
                return Ok(old);
            }
        }
        match existing_lock(s(&p["bulkLock"]), true) {
            Err(e)
                if e.downcast_ref::<std::io::Error>()
                    .is_some_and(|e| e.kind() == std::io::ErrorKind::WouldBlock) =>
            {
                r["status"] = json!("deferred")
            }
            Err(e) => return Err(e),
            Ok(_lock) => {
                let minimum = n(&p["minimumMemoryAvailableBytes"]);
                let text = fs::read_to_string("/proc/meminfo").unwrap_or_default();
                let memory = text
                    .lines()
                    .find(|l| l.starts_with("MemAvailable:"))
                    .and_then(|l| l.split_whitespace().nth(1))
                    .and_then(|v| v.parse::<u64>().ok())
                    .unwrap_or(0)
                    * 1024;
                if memory < minimum {
                    r["status"] = json!("deferred-memory");
                } else {
                    let before = n(&mounted(c)?["available"]);
                    r["beforeBytes"] = json!(before);
                    if before < n(&p["collectBelowBytes"]) {
                        let command = vec![
                            s(&p["nixStore"]).into(),
                            "--store".into(),
                            "daemon".into(),
                            "--gc".into(),
                            "--max-freed".into(),
                            n(&p["collectTargetBytes"])
                                .saturating_sub(before)
                                .to_string(),
                        ];
                        let out = output_tail(&command, 1800, 65536)?;
                        let mut tail = out.stdout;
                        tail.extend(out.stderr);
                        if tail.len() > 65536 {
                            tail.drain(..tail.len() - 65536);
                        }
                        let log = state(p, "collection.log");
                        fs::write(&log, tail)?;
                        fs::set_permissions(log, fs::Permissions::from_mode(0o600))?;
                        let after = n(&mounted(c)?["available"]);
                        r["exitCode"] = json!(out.status.code().unwrap_or(-1));
                        r["afterBytes"] = json!(after);
                        r["targetReached"] = json!(after >= n(&p["collectTargetBytes"]));
                        r["status"] = json!(if !out.status.success() {
                            "failed"
                        } else if after >= n(&p["collectBelowBytes"]) {
                            "collected"
                        } else {
                            "unreclaimable"
                        });
                    }
                }
            }
        }
    }
    if ["skipped", "collected"].contains(&s(&r["status"])) {
        r.as_object_mut()
            .ok_or("Receipt")?
            .remove("previousFailure");
    }
    if r["afterBytes"].is_null() {
        r["afterBytes"] = mounted(c)?["available"].clone();
    }
    r["completed"] = json!(now());
    save_collection(p, &r)?;
    Ok(r)
}
fn main() {
    entry(|| {
        let a = args();
        let p = read(option(&a, "--policy").ok_or_else(|| usage_error("--policy required"))?)?;
        let command = a
            .iter()
            .find(|x| ["status", "cache", "collect", "snapshot", "admit"].contains(&x.as_str()))
            .ok_or_else(|| usage_error("Command required"))?;
        let r = match command.as_str() {
            "status" => status(&p)?,
            "cache" => cache(&p)?,
            "collect" => collect(&p, a.iter().any(|v| v == "--force"))?,
            _ => {
                let recovery = a.iter().any(|v| v == "--recovery");
                let mut requests = Vec::new();
                if command == "snapshot" {
                    requests.push((
                        a.get(a.iter().position(|v| v == "snapshot").ok_or("snapshot")? + 1)
                            .ok_or_else(|| usage_error("Snapshot path"))?
                            .clone(),
                        0,
                    ));
                    requests.push(("/".into(), 0));
                } else {
                    for w in a.windows(2).filter(|w| w[0] == "--disk-mib") {
                        let (path, value) = w[1].rsplit_once('=').ok_or("Disk request PATH=MiB")?;
                        if value.is_empty()
                            || value.len() > 12
                            || !value.bytes().all(|b| b.is_ascii_digit())
                        {
                            return fail("Disk request PATH=nonnegative_MiB");
                        }
                        requests.push((
                            path.into(),
                            value
                                .parse::<u64>()?
                                .checked_mul(1048576)
                                .ok_or("Request overflow")?,
                        ));
                    }
                    let default = if recovery || !requests.is_empty() {
                        0
                    } else {
                        n(&p["defaultAdditionalBytes"])
                    };
                    requests.push(("/".into(), default));
                    requests.push((std::env::current_dir()?.to_string_lossy().into_owned(), 0));
                }
                let r = admission(&p, requests, recovery, command == "snapshot")?;
                if let Some(path) = option(&a, "--receipt") {
                    save(path, &r, 0o600)?;
                }
                r
            }
        };
        if r["admitted"] == false
            || command == "collect" && ["failed", "unreclaimable"].contains(&s(&r["status"]))
        {
            eprintln!("{r}");
            return Ok(75);
        }
        println!("{r}");
        Ok(0)
    })
}
