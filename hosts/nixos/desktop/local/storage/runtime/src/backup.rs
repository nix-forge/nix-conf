use crate::*;
use std::os::unix::fs::MetadataExt;
const PHASES: &[&str] = &[
    "backup",
    "integrity",
    "restore",
    "cold-backup",
    "cold-restore",
    "database-backup",
];
fn receipt(p: &Value, name: &str, phase: &str) -> PathBuf {
    state(p, &format!("checks/{name}-{phase}.json"))
}
pub fn stamp(p: &Value, name: &str, phase: &str) -> Result<()> {
    save(
        receipt(p, name, phase),
        &json!({"completed":now(),"phase":phase}),
        0o644,
    )
}
fn read_stamp(p: &Value, name: &str, phase: &str) -> f64 {
    let value = read(receipt(p, name, phase))
        .ok()
        .and_then(|v| v["completed"].as_f64())
        .unwrap_or(0.);
    if value > 0. && value <= now() + 60. {
        value
    } else {
        0.
    }
}
fn guard(policy: &Value, d: &Value) -> Result<()> {
    for key in ["repositoryFile", "passwordFile", "environmentFile"] {
        if !s(&d[key]).is_empty() {
            let path = fs::canonicalize(s(&d[key]))?;
            let m = fs::metadata(&path)?;
            if !m.is_file()
                || m.uid() != 0
                || m.mode() & 0o077 != 0
                || path.starts_with("/nix/store")
            {
                return fail(
                    "Credential files must be root-owned private regular files outside the store",
                );
            }
        }
    }
    let mounts = list(&d["requiredMounts"]);
    for path in &mounts {
        cmd(&["mountpoint", "-q", path])?;
    }
    let repository = fs::read_to_string(s(&d["repositoryFile"]))?;
    let repository = repository.trim();
    if repository.is_empty() {
        return fail("Repository file is empty");
    }
    if !repository.contains(':')
        || regex::Regex::new(r"^(?:local:|/|\\|\.\.[/\\]|[a-zA-Z]:[/\\])")?.is_match(repository)
    {
        let target = resolve_missing(Path::new(
            repository.strip_prefix("local:").unwrap_or(repository),
        ))?;
        let roots = mounts
            .iter()
            .map(fs::canonicalize)
            .collect::<std::io::Result<Vec<_>>>()?;
        if !roots.iter().any(|r| target.starts_with(r)) {
            return fail("Local repositories require explicit external mount point");
        }
        let device = cmd(&[
            "findmnt",
            "-n",
            "-o",
            "MAJ:MIN",
            "-T",
            &target.to_string_lossy(),
        ])?;
        for source in ["/", policy_path(policy, "dataMount", LEGACY_DATA_MOUNT)?] {
            if cmd(&["findmnt", "-n", "-o", "MAJ:MIN", "-T", source])?.trim() == device.trim() {
                return fail("Backup repository must not use a source filesystem");
            }
        }
    }
    Ok(())
}
fn resolve_missing(path: &Path) -> Result<PathBuf> {
    if path.exists() {
        return Ok(fs::canonicalize(path)?);
    }
    let absolute = std::path::absolute(path)?;
    let parent = absolute.parent().ok_or("Repository parent")?;
    Ok(resolve_missing(parent)?.join(absolute.file_name().ok_or("Repository name")?))
}
fn canary(p: &Value) -> Result<PathBuf> {
    let path = state(p, "restore-canary");
    fs::create_dir_all(path.parent().ok_or("Canary parent")?)?;
    if !path.exists() {
        let mut random = [0; 512];
        File::open("/dev/urandom")?.read_exact(&mut random)?;
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&path)?;
        for b in random {
            write!(file, "{b:02x}")?;
        }
        writeln!(file)?;
    }
    Ok(path)
}
fn restore(p: &Value, name: &str, tag: &str) -> Result<()> {
    let expected = canary(p)?;
    let snaps: Value = serde_json::from_str(&cmd(&[
        "restic",
        "snapshots",
        "--json",
        "--tag",
        tag,
        "--latest",
        "1",
    ])?)?;
    let snapshots = snaps.as_array().ok_or("Snapshots")?;
    if snapshots.len() != 1 {
        return fail("Expected one latest snapshot; check repository scope");
    }
    let cache = std::env::var("CACHE_DIRECTORY").unwrap_or("/var/cache".into());
    let tmp = tempfile::Builder::new()
        .prefix(&format!("desktop-restore-{name}-"))
        .tempdir_in(cache)?;
    let parent = expected.parent().ok_or("Canary parent")?;
    let file = expected.file_name().ok_or("Canary name")?.to_string_lossy();
    cmd(&[
        "restic",
        "restore",
        &format!("{}:{}", s(&snapshots[0]["id"]), parent.display()),
        "--target",
        &tmp.path().to_string_lossy(),
        "--include",
        &format!("/{file}"),
        "--verify",
    ])?;
    let recovered = tmp.path().join(file.as_ref());
    if recovered.is_symlink() || fs::read(recovered)? != fs::read(expected)? {
        return fail("Restored canary did not match source");
    }
    Ok(())
}
fn journal(p: &Value) -> PathBuf {
    state(p, "native-operation.json")
}
pub fn recover(p: &Value) -> Result<()> {
    let journal = journal(p);
    if !journal.exists() {
        return Ok(());
    }
    let record = read(&journal)?;
    if !record["active"]
        .as_array()
        .is_some_and(|a| a.iter().all(Value::is_string))
        || !record["guards"]
            .as_array()
            .is_some_and(|a| a.iter().all(Value::is_string))
        || s(&record["body"]).is_empty()
    {
        return fail("Malformed native recovery journal; inspect before recovery");
    }
    for name in list(&record["guards"]) {
        let path = Path::new(&name);
        if path.exists() || path.is_symlink() {
            if path.is_symlink() || fs::read_to_string(path)? != s(&record["body"]) {
                return fail("Native backup activation guard changed; recovery needs review");
            }
            fs::remove_file(path)?;
        }
    }
    cmd(&["systemctl", "daemon-reload"])?;
    let mut failed = false;
    for unit in list(&record["active"]).iter().rev() {
        if cmd(&["systemctl", "start", unit]).is_err()
            || cmd(&[
                "systemctl",
                "show",
                unit,
                "--property=ActiveState",
                "--value",
            ])
            .map_or(true, |v| v.trim() != "active")
        {
            failed = true;
        }
    }
    if failed {
        return fail("Native backup could not restart every original writer");
    }
    fs::remove_file(journal)?;
    Ok(())
}
fn prepare(p: &Value) -> Result<()> {
    let journal = journal(p);
    if journal.exists() {
        return fail("Interrupted native backup requires recovery first");
    }
    let units = list(&p["coldUnits"]);
    let re = regex::Regex::new(r"^[a-zA-Z0-9@_.:-]+\.(?:service|mount|timer|socket)$")?;
    let unique: std::collections::BTreeSet<_> = units.iter().collect();
    if units.is_empty() || unique.len() != units.len() || units.iter().any(|u| !re.is_match(u)) {
        return fail("Invalid native backup units");
    }
    let guarddir = if s(&p["nativeGuardDirectory"]).is_empty() {
        "/run/systemd/system.control"
    } else {
        s(&p["nativeGuardDirectory"])
    };
    let guards: Vec<_> = units
        .iter()
        .map(|u| Path::new(guarddir).join(format!("{u}.d/90-desktop-native-backup.conf")))
        .collect();
    if guards.iter().any(|p| p.exists() || p.is_symlink()) {
        return fail("Native backup activation guard already exists");
    }
    let mut active = Vec::new();
    for u in &units {
        let text = cmd(&["systemctl", "show", u, "--property=LoadState,ActiveState"])?;
        let values: std::collections::BTreeMap<_, _> =
            text.lines().filter_map(|l| l.split_once('=')).collect();
        if values.get("LoadState") != Some(&"loaded")
            || !matches!(
                values.get("ActiveState"),
                Some(&"active") | Some(&"inactive")
            )
        {
            return fail("Native backup writer unavailable or transitioning");
        }
        if values.get("ActiveState") == Some(&"active") {
            active.push(u);
        }
    }
    let body = format!("[Unit]\nConditionPathExists=!{}\n", journal.display());
    fs::create_dir_all(journal.parent().ok_or("Journal parent")?)?;
    let mut temporary = tempfile::NamedTempFile::new_in(journal.parent().ok_or("Journal parent")?)?;
    serde_json::to_writer(
        &mut temporary,
        &json!({"active":active,"guards":guards.iter().map(|p|p.to_string_lossy()).collect::<Vec<_>>(),"body":body}),
    )?;
    temporary.as_file().sync_all()?;
    fs::hard_link(temporary.path(), journal)?;
    for path in guards {
        fs::create_dir_all(path.parent().ok_or("Guard parent")?)?;
        OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(path)?
            .write_all(body.as_bytes())?;
    }
    cmd(&["systemctl", "daemon-reload"])?;
    let mut stop = vec!["systemctl".into(), "stop".into()];
    stop.extend(units.clone());
    run(&stop)?;
    for unit in units {
        if cmd(&[
            "systemctl",
            "show",
            &unit,
            "--property=ActiveState",
            "--value",
        ])?
        .trim()
            != "inactive"
        {
            return fail("Native backup writer did not stop");
        }
    }
    for path in list(&p["coldUnmounts"]) {
        let out = output(
            &[
                "findmnt".into(),
                "--noheadings".into(),
                "--mountpoint".into(),
                path,
            ],
            30,
            None,
        )?;
        if out.status.code() != Some(1) {
            return fail("Native image filesystem is mounted or mount inspection failed");
        }
    }
    Ok(())
}
fn manifest(paths: &[String], root: Option<&Path>) -> Result<Value> {
    let mut out = json!({});
    fn visit(path: &Path, key: &Path, out: &mut Value) -> Result<()> {
        let m = fs::symlink_metadata(path)?;
        let mut item = json!({"mode":m.mode()&0o7777,"uid":m.uid(),"gid":m.gid()});
        if m.is_symlink() {
            item["symlink"] = json!(fs::read_link(path)?.to_string_lossy());
        } else if m.is_file() {
            item["sha256"] = fingerprint_readonly(path)?;
        } else if !m.is_dir() {
            return fail("Native backup contains unsupported file type");
        }
        out[key.to_string_lossy().as_ref()] = item;
        if m.is_dir() {
            let mut entries = fs::read_dir(path)?
                .map(|e| e.map(|e| e.path()))
                .collect::<std::io::Result<Vec<_>>>()?;
            entries.sort();
            for child in entries {
                visit(
                    &child,
                    &key.join(child.file_name().ok_or("File name")?),
                    out,
                )?;
            }
        }
        Ok(())
    }
    for name in paths {
        let original = Path::new(name);
        let path = root
            .map(|r| r.join(original.strip_prefix("/").unwrap_or(original)))
            .unwrap_or_else(|| original.to_owned());
        if path.is_symlink() {
            return fail("Native backup roots must not be symlinks");
        }
        visit(&path, original, &mut out)?;
    }
    Ok(out)
}
fn fingerprint_readonly(path: &Path) -> Result<Value> {
    let mut f = File::open(path)?;
    let mut h = Sha256::new();
    let mut b = [0; 65536];
    loop {
        let got = f.read(&mut b)?;
        if got == 0 {
            break;
        }
        h.update(&b[..got]);
    }
    Ok(json!(format!("{}", base16ct::HexDisplay(&h.finalize()))))
}
fn native_backup(p: &Value, name: &str) -> Result<()> {
    // Policies without this field used the workstation-wide lock.
    let lock_path = policy_path(p, "bulkLock", "/run/workstation-workloads/bulk.lock")?;
    let _lock = lock(lock_path, false)?;
    if journal(p).exists() {
        return fail("Interrupted native backup requires recovery first");
    }
    let captured = (|| -> Result<(Value, String)> {
        prepare(p)?;
        let command = list(&p["coldPrepareCommand"]);
        if !command.is_empty() {
            run(&command)?;
        }
        let paths = list(&p["coldPaths"]);
        let expected = manifest(&paths, None)?;
        let mut a = vec![
            s(&p["coldRestic"]).into(),
            "backup".into(),
            "--json".into(),
            "--tag".into(),
            "desktop-cold".into(),
        ];
        a.extend(paths.clone());
        let output = run(&a)?;
        let mut snapshot = None;
        for line in output.lines() {
            let v: Value = serde_json::from_str(line)?;
            if v["message_type"] == "summary" {
                snapshot = Some(s(&v["snapshot_id"]).to_owned());
            }
        }
        if manifest(&paths, None)? != expected {
            return fail("Native source changed while writers were stopped");
        }
        Ok((
            expected,
            snapshot
                .filter(|v| !v.is_empty())
                .ok_or("No snapshot summary")?,
        ))
    })();
    let recovery = recover(p);
    let (expected, snapshot) = captured?;
    recovery?;
    stamp(p, name, "cold-backup")?;
    let cache = if !s(&p["coldRestoreScratch"]).is_empty() {
        s(&p["coldRestoreScratch"]).to_owned()
    } else {
        std::env::var("CACHE_DIRECTORY").unwrap_or("/var/cache".into())
    };
    let tmp = tempfile::Builder::new()
        .prefix("native-restore-")
        .tempdir_in(cache)?;
    let paths = list(&p["coldPaths"]);
    for source in &paths {
        let source = Path::new(source);
        let parent = source.parent().ok_or("Source parent")?;
        let target = tmp.path().join(parent.strip_prefix("/").unwrap_or(parent));
        fs::create_dir_all(&target)?;
        cmd(&[
            s(&p["coldRestic"]),
            "restore",
            &format!("{snapshot}:{}", parent.display()),
            "--target",
            &target.to_string_lossy(),
            "--include",
            &format!(
                "/{}",
                source.file_name().ok_or("Source name")?.to_string_lossy()
            ),
            "--verify",
        ])?;
    }
    if manifest(&paths, Some(tmp.path()))? != expected {
        return fail("Native application restore did not match captured files");
    }
    save(
        receipt(p, name, "native-restore"),
        &json!({"completed":now(),"snapshot":snapshot,"filesVerified":expected.as_object().ok_or("Manifest")?.values().filter(|v|!v["sha256"].is_null()||!v["symlink"].is_null()).count(),"scope":"full-native-cold-paths"}),
        0o600,
    )?;
    stamp(p, name, "cold-restore")
}
fn cold_guard(policy: &Value) -> Result<()> {
    cmd(&["systemctl", "is-active", "--quiet", "rescue.target"])?;
    let units = cmd(&[
        "systemctl",
        "list-units",
        "--state=active,activating",
        "--no-legend",
        "--plain",
    ])?;
    if units.split_whitespace().any(|v| {
        v.starts_with("user@") || ["multi-user.target", "graphical-session.target"].contains(&v)
    }) {
        return fail("Stop user managers and leave multi-user mode before cold backup");
    }
    let processes = cmd(&["ps", "-eo", "comm="])?;
    if processes.lines().any(|v| {
        [
            "qemu-system",
            "qemu-kvm",
            "dockerd",
            "containerd",
            "podman",
            "conmon",
            "runc",
        ]
        .iter()
        .any(|prefix| v.trim().starts_with(prefix))
    }) {
        return fail("Stop all VM and container processes before cold backup");
    }
    let vm_images_mount = policy_path(policy, "vmImagesMount", "/var/lib/libvirt/images")?;
    cmd(&["mountpoint", "-q", vm_images_mount])?;
    Ok(())
}
pub fn main_cli() -> Result<i32> {
    let a = args();
    let p = read(a.first().ok_or_else(|| usage_error("Policy required"))?)?;
    let action = a.get(1).map(String::as_str).unwrap_or("status");
    if action == "status" {
        let destinations = p["destinations"].as_object().ok_or("Destinations")?;
        let mut messages = Vec::new();
        if destinations.len() < 2 {
            messages.push(
                "Two independent backup destinations are required in addition to the working copy"
                    .into(),
            );
        }
        if destinations
            .values()
            .map(|d| s(&d["failureDomain"]))
            .collect::<std::collections::BTreeSet<_>>()
            .len()
            < 2
        {
            messages.push("Independent backup failure domains are not fully declared".into());
        }
        if !destinations
            .values()
            .any(|d| !["ssd", "unknown"].contains(&s(&d["medium"])))
        {
            messages.push("A second storage medium beyond the source SSDs is not declared".into());
        }
        if !destinations.values().any(|d| d["offsite"] == true) {
            messages.push("An off-site backup is not declared".into());
        }
        if !destinations
            .values()
            .any(|d| ["offline", "immutable"].contains(&s(&d["protection"])))
        {
            messages.push("An offline or externally immutable copy is not declared".into());
        }
        for (name, d) in destinations {
            let mut phases = vec![
                ("backup", n(&d["maxAgeHours"]) * 3600),
                ("integrity", n(&d["maxVerificationAgeDays"]) * 86400),
                ("restore", n(&d["maxVerificationAgeDays"]) * 86400),
                ("recovery-drill", 90 * 86400),
            ];
            if p["coldRequired"] != false {
                let age = d["maxColdAgeDays"].as_u64().unwrap_or(14) * 86400;
                phases.extend([("cold-backup", age), ("cold-restore", age)]);
            }
            for (phase, max) in phases {
                let t = read_stamp(&p, name, phase);
                if t == 0. || now() - t > max as f64 {
                    messages.push(format!("{name}: {phase} is missing or overdue"));
                }
            }
            for operation in ["backup", "verification", "cold", "database-backup"] {
                let failed = read_stamp(&p, name, &format!("{operation}-failure"));
                if failed > 0. && failed >= read_stamp(&p, name, &format!("{operation}-success")) {
                    messages.push(format!("{name}: latest {operation} attempt failed"));
                }
            }
        }
        println!("3-2-1-1-0 backup status");
        for m in &messages {
            println!("- {m}");
        }
        if messages.is_empty() {
            println!("Declared topology and recorded checks are current.");
        }
        println!(
            "Physical independence, off-site location and immutability require external verification.\nAutomated restore covers a canary; application recovery requires a separate drill."
        );
        return Ok(i32::from(!messages.is_empty()));
    }
    root()?;
    let name = a.get(2).map(String::as_str).unwrap_or("");
    let phase = a.get(3).map(String::as_str).unwrap_or("");
    if !["canary", "recover-native"].contains(&action) && p["destinations"].get(name).is_none() {
        return usage("Unknown backup destination");
    }
    match action {
        "guard" => guard(&p, &p["destinations"][name])?,
        "stamp" => {
            if !PHASES.contains(&phase) {
                return usage("stamp requires a phase");
            }
            stamp(&p, name, phase)?;
        }
        "finish" => {
            if !["backup", "verification", "cold", "database-backup"].contains(&phase) {
                return usage("finish requires an operation");
            }
            stamp(
                &p,
                name,
                &format!(
                    "{phase}-{}",
                    if std::env::var("SERVICE_RESULT").as_deref() == Ok("success") {
                        "success"
                    } else {
                        "failure"
                    }
                ),
            )?;
        }
        "canary" => {
            canary(&p)?;
        }
        "restore" => restore(&p, name, "desktop-files")?,
        "recover-native" => recover(&p)?,
        "cold-backup" => {
            guard(&p, &p["destinations"][name])?;
            if !list(&p["coldUnits"]).is_empty() {
                native_backup(&p, name)?;
            } else {
                cold_guard(&p)?;
                let expected = canary(&p)?;
                let mut a = vec![
                    "restic".into(),
                    "backup".into(),
                    "--tag".into(),
                    "desktop-cold".into(),
                ];
                a.extend(
                    list(&p["coldPaths"])
                        .into_iter()
                        .filter(|p| Path::new(p).exists()),
                );
                a.push(expected.to_string_lossy().into_owned());
                run(&a)?;
                cold_guard(&p)?;
                stamp(&p, name, "cold-backup")?;
                restore(&p, name, "desktop-cold")?;
                stamp(&p, name, "cold-restore")?;
            }
        }
        "record-recovery-drill" => {
            println!(
                "After restoring real files and testing application recovery independently, type 'recovery tested': "
            );
            let mut answer = String::new();
            std::io::stdin().read_line(&mut answer)?;
            if answer.trim_end() != "recovery tested" {
                return fail("Recovery drill was not confirmed");
            }
            stamp(&p, name, "recovery-drill")?;
        }
        _ => return usage("Unknown backup operation"),
    };
    Ok(0)
}

// Restic receives INT and a flush window before group KILL on interruption.
fn run(a: &[String]) -> Result<String> {
    let o = crate::output_capture(a, 86400, None, None, 300)?;
    if !o.status.success() {
        return fail("Backup utility failed; inspect the owning service privately");
    }
    Ok(String::from_utf8(o.stdout)?)
}
fn cmd(a: &[&str]) -> Result<String> {
    run(&a.iter().map(|v| (*v).to_string()).collect::<Vec<_>>())
}
