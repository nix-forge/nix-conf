use desktop_storage_runtime::*;
use serde_json::{Value, json};
use std::{fs, path::Path};
fn bounded(a: &[&str]) -> Result<std::process::Output> {
    output(
        &a.iter().map(|v| (*v).to_owned()).collect::<Vec<_>>(),
        30,
        None,
    )
}
fn btrfs(p: &Value, path: &str) -> Result<Vec<String>> {
    let report = state(p, &format!("btrfs-{}.json", hash(path.as_bytes())));
    let previous = optional(&report)?;
    let out = bounded(&["btrfs", "device", "stats", path])?;
    if !out.status.success() {
        return fail("Device stats failed");
    }
    let text = String::from_utf8(out.stdout)?;
    let mut counters = json!({});
    for line in text.lines() {
        let (key, value) = line
            .rsplit_once(char::is_whitespace)
            .ok_or("Malformed device statistics")?;
        if !key.starts_with('[') || !key.contains("].") {
            return fail("Malformed device statistics");
        }
        counters[key.trim_end()] = json!(value.trim().parse::<u64>()?);
    }
    let c = counters.as_object().ok_or("Counters")?;
    if c.is_empty() {
        return fail("Missing device statistics");
    }
    let mut messages = Vec::new();
    if c.iter()
        .any(|(k, v)| n(v) > previous["counters"][k].as_u64().unwrap_or(n(v)))
    {
        messages.push(format!(
            "New Btrfs device errors on {path}; investigate integrity"
        ));
    } else if c
        .iter()
        .any(|(k, v)| n(v) < previous["counters"][k].as_u64().unwrap_or(n(v)))
    {
        messages.push(format!(
            "Btrfs device counters decreased or were reset on {path}; review preserved evidence"
        ));
    } else if c.values().any(|v| n(v) > 0) {
        messages.push(format!("Historical Btrfs device errors remain on {path}; latest scrub and counter deltas need review"));
    }
    save(
        report,
        &json!({"checked":now(),"counters":counters,"previous":previous.get("counters").cloned().unwrap_or(json!({}))}),
        0o600,
    )?;
    Ok(messages)
}
fn allocation(p: &Value, path: &str) -> Result<Vec<String>> {
    let out = bounded(&["btrfs", "filesystem", "usage", "--raw", path])?;
    if !out.status.success() {
        return fail("Usage failed");
    }
    let text = String::from_utf8(out.stdout)?;
    let re = regex::Regex::new(r"(?m)^Metadata,[^:]+: Size:(\d+), Used:(\d+)")?;
    let mut allocated = 0u64;
    let mut used = 0u64;
    let mut count = 0;
    for c in re.captures_iter(&text) {
        allocated += c[1].parse::<u64>()?;
        used += c[2].parse::<u64>()?;
        count += 1;
    }
    let reserve_re = regex::Regex::new(r"Global reserve:\s*(\d+)\s+\(used:\s*(\d+)\)")?;
    let reserve = reserve_re.captures(&text).ok_or("Reserve unavailable")?;
    let unallocated_re = regex::Regex::new(r"Device unallocated:\s*(\d+)")?;
    let unallocated = unallocated_re
        .captures(&text)
        .ok_or("Unallocated unavailable")?[1]
        .parse::<u64>()?;
    if count == 0 {
        return fail("Metadata fields unavailable");
    }
    let reserve_used = reserve[2].parse::<u64>()?;
    save(
        state(p, &format!("allocation-{}.json", hash(path.as_bytes()))),
        &json!({"checked":now(),"metadataAllocatedLogicalBytes":allocated,"metadataUsedLogicalBytes":used,"globalReserveBytes":reserve[1].parse::<u64>()?,"globalReserveUsedBytes":reserve_used,"unallocatedDeviceBytes":unallocated}),
        0o600,
    )?;
    Ok(if reserve_used > 0 {
        vec![format!(
            "Btrfs emergency metadata reserve is in use: {path}"
        )]
    } else if allocated.saturating_sub(used) < 256 * 1024 * 1024 && unallocated < 1024 * 1024 * 1024
    {
        vec![format!("Btrfs metadata allocation headroom is low: {path}")]
    } else {
        Vec::new()
    })
}
fn mount(p: &Value, path: &str) -> Result<Vec<String>> {
    let out = bounded(&[
        "findmnt",
        "--nocanonicalize",
        "--list",
        "--json",
        "--mountpoint",
        path,
        "--output",
        "TARGET,FSTYPE",
    ])?;
    if !out.status.success() {
        return Ok(vec![format!("Storage is not mounted: {path}")]);
    }
    let v: Value = serde_json::from_slice(&out.stdout)?;
    if !v["filesystems"]
        .as_array()
        .ok_or("Mounts")?
        .iter()
        .any(|m| m["target"] == path && !s(&m["fstype"]).is_empty() && m["fstype"] != "autofs")
    {
        return Ok(vec![format!("Storage is not mounted: {path}")]);
    }
    let mut messages = Vec::new();
    if list(&p["capacityCommand"]).is_empty() {
        let u = rustix::fs::statvfs(path)?;
        if u.f_blocks == 0 {
            return fail("Empty filesystem usage");
        }
        let used = 100. * (u.f_blocks - u.f_bfree) as f64 / u.f_blocks as f64;
        if used >= n(&p["warningPercent"]) as f64 {
            messages.push(format!("Low free space on {path}: {used:.0}% used"));
        }
    }
    messages.extend(btrfs(p, path).unwrap_or_else(|_| {
        vec![format!(
            "Btrfs device statistics could not be inspected: {path}"
        )]
    }));
    messages.extend(
        allocation(p, path)
            .unwrap_or_else(|_| vec![format!("Btrfs allocation could not be inspected: {path}")]),
    );
    Ok(messages)
}
fn collect(p: &Value) -> Result<Vec<String>> {
    let mut messages = Vec::new();
    if p["encrypted"] != true {
        messages.push("Disk encryption migration is not enabled".into());
    }
    let a = list(&p["capacityCommand"]);
    if !a.is_empty() {
        let capacity = (|| -> Result<Vec<String>> {
            let out = output(&a, 30, None)?;
            if !out.status.success() {
                return fail("Capacity failed");
            }
            let v: Value = serde_json::from_slice(&out.stdout)?;
            strings(&v["messages"])
        })();
        messages.extend(
            capacity
                .unwrap_or_else(|_| vec!["Storage capacity policy could not be checked".into()]),
        );
    }
    for path in list(&p["mounts"]) {
        messages.extend(
            mount(p, &path).unwrap_or_else(|_| vec![format!("Storage inspection failed: {path}")]),
        );
    }
    for unit in list(&p["units"]) {
        let result = (|| -> Result<bool> {
            let out = bounded(&[
                "systemctl",
                "show",
                &unit,
                "--property=LoadState,ActiveState",
            ])?;
            let text = String::from_utf8(out.stdout)?;
            let fields: std::collections::BTreeMap<_, _> =
                text.lines().filter_map(|l| l.split_once('=')).collect();
            Ok(out.status.success()
                && fields.get("LoadState") == Some(&"loaded")
                && fields.get("ActiveState") != Some(&"failed"))
        })();
        if !matches!(result, Ok(true)) {
            messages.push(format!("Service needs attention: {unit}"));
        }
    }
    match bounded(&["desktop-backup-check", "status"]) {
        Ok(out) if !out.status.success() => {
            let text = String::from_utf8_lossy(&out.stdout);
            messages.extend(
                text.lines()
                    .filter_map(|l| l.strip_prefix("- ").map(str::to_owned)),
            );
            if text.is_empty() {
                messages.push("Backup status could not be checked".into());
            }
        }
        Err(_) => messages.push("Backup status could not be checked".into()),
        _ => {}
    }
    if let Some(probes) = p["probes"].as_object() {
        for (name, probe) in probes {
            let result = (|| -> Result<()> {
                let a = list(&probe["command"]);
                if !a.is_empty()
                    && !output(&a, n(&probe["timeoutSeconds"]), None)?
                        .status
                        .success()
                {
                    messages.push(format!("Service probe failed: {name}"));
                }
                if !s(&probe["receipt"]).is_empty() {
                    let record = read(s(&probe["receipt"]))?;
                    let age = now() - record["completed"].as_f64().ok_or("Receipt time")?;
                    if !age.is_finite()
                        || age < -60.
                        || age > n(&probe["maxAgeSeconds"]) as f64
                        || record.get("result").is_some_and(|v| v != "success")
                    {
                        messages.push(format!("Successful work is missing or overdue: {name}"));
                    }
                }
                Ok(())
            })();
            if result.is_err() {
                messages.push(format!("Service probe unavailable: {name}"));
            }
        }
    }
    Ok(messages)
}
fn strings(v: &Value) -> Result<Vec<String>> {
    v.as_array()
        .ok_or("Messages must be an array")?
        .iter()
        .map(|v| {
            v.as_str()
                .map(str::to_owned)
                .ok_or_else(|| "Messages must be strings".into())
        })
        .collect()
}
fn report(p: &Value) -> Vec<String> {
    match read(state(p, "health.json")) {
        Ok(v) => {
            let age = v["checked"].as_f64().map(|t| now() - t);
            if age.is_none_or(|a| !a.is_finite() || !(-60. ..=7200.).contains(&a)) {
                return vec![
                    "Storage health results are stale; inspect desktop-storage-health.service"
                        .into(),
                ];
            }
            strings(&v["messages"])
                .unwrap_or_else(|_| vec!["Storage health report is malformed".into()])
        }
        Err(_) => vec!["Storage health has not been checked yet".into()],
    }
}
fn deliver(p: &Value, messages: Vec<String>, desktop: bool, test: bool) -> Result<i32> {
    let directory =
        if desktop {
            Path::new(&std::env::var("XDG_CACHE_HOME").unwrap_or_else(|_| {
                format!("{}/.cache", std::env::var("HOME").unwrap_or_default())
            }))
            .join("desktop-storage")
        } else {
            state(p, "delivery")
        };
    fs::create_dir_all(&directory)?;
    use std::os::unix::fs::PermissionsExt;
    fs::set_permissions(&directory, fs::Permissions::from_mode(0o700))?;
    let _lock = lock(&directory.join("lock").to_string_lossy(), false)?;
    let previous = optional(directory.join("delivered.json")).unwrap_or(json!({}));
    let unique: std::collections::BTreeSet<_> = messages.iter().collect();
    let channel = if desktop {
        json!("desktop")
    } else {
        p["notificationCommand"].clone()
    };
    let digest = receipt_hash(&json!({"messages":unique,"channel":channel}))?;
    let event = json!({"event":if test{"test"}else if messages.is_empty(){"recovery"}else{"warning"},"messages":messages});
    let pending = directory.join(if test {
        "test-pending.json"
    } else {
        "pending.json"
    });
    if !test
        && (previous["digest"] == digest
            || messages.is_empty() && previous.as_object().is_some_and(|p| p.is_empty()))
    {
        if pending.exists() {
            fs::remove_file(pending)?;
        }
        return Ok(0);
    }
    save(&pending, &event, 0o600)?;
    let a = if desktop {
        vec![
            "notify-send".into(),
            if messages.is_empty() {
                "--urgency=normal".into()
            } else {
                "--urgency=critical".into()
            },
            "--expire-time=0".into(),
            if messages.is_empty() {
                "Workstation checks recovered".into()
            } else {
                "Workstation needs attention".into()
            },
            if messages.is_empty() {
                "Previously reported checks now pass.".into()
            } else {
                messages.join("\n")
            },
        ]
    } else {
        list(&p["notificationCommand"])
    };
    if a.is_empty() {
        return Ok(i32::from(test));
    }
    let payload = format!("{event}\n");
    if output(&a, 30, Some(payload.as_bytes())).map_or(true, |o| !o.status.success()) {
        return Ok(1);
    }
    if !test {
        save(
            directory.join("delivered.json"),
            &json!({"digest":digest,"event":event["event"],"completed":now()}),
            0o600,
        )?;
    }
    fs::remove_file(pending)?;
    Ok(0)
}
fn main() {
    entry(|| {
        let a = args();
        let p = read(a.first().ok_or_else(|| usage_error("Policy required"))?)?;
        let action = a.get(1).map(String::as_str).unwrap_or("status");
        if action == "refresh" {
            root()?;
            fs::create_dir_all(state(&p, ""))?;
            let messages = collect(&p)?;
            save(
                state(&p, "health.json"),
                &json!({"checked":now(),"messages":messages}),
                0o644,
            )?;
            println!(
                "{}",
                if messages.is_empty() {
                    "Storage checks passed".into()
                } else {
                    messages.join("\n")
                }
            );
            return Ok(0);
        }
        let messages = report(&p);
        if ["notify", "deliver", "test-delivery"].contains(&action) {
            return deliver(&p, messages, action == "notify", action == "test-delivery");
        }
        if action != "status" {
            return usage("Unknown health operation");
        }
        if messages.is_empty() {
            println!("Storage checks passed");
        }
        for m in &messages {
            println!("- {m}");
        }
        Ok(i32::from(!messages.is_empty()))
    })
}
