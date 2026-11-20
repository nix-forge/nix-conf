use desktop_storage_runtime::*;
use serde_json::{Value, json};
use std::{
    fs,
    os::unix::fs::{MetadataExt, PermissionsExt, symlink},
    path::Path,
};
fn identity(path: &str) -> Result<String> {
    let bin = Path::new(path).join("bin");
    Ok(if bin.exists() {
        fs::canonicalize(bin)?.to_string_lossy().into_owned()
    } else {
        path.to_owned()
    })
}
fn plan(p: &Value) -> Result<Value> {
    let c = &p["generations"];
    let profile = Path::new(s(&c["profile"]));
    let current = fs::canonicalize(s(&c["currentSystem"]))?;
    let booted = fs::canonicalize(s(&c["bootedSystem"]))?;
    if identity(&fs::canonicalize(profile)?.to_string_lossy())?
        != identity(&current.to_string_lossy())?
    {
        return fail("System activation is not settled; refusing generation retirement");
    }
    let mut protected = std::collections::BTreeSet::from([
        current.to_string_lossy().into_owned(),
        booted.to_string_lossy().into_owned(),
    ]);
    let pattern = regex::Regex::new(&format!(r"^{}-\d+-link$", regex::escape(s(&c["profile"]))))?;
    if !s(&c["nixStore"]).is_empty() {
        for line in cmd(&[s(&c["nixStore"]), "--gc", "--print-roots"])?.lines() {
            let (root, target) = line.rsplit_once(" -> ").ok_or("Malformed GC root")?;
            let root = if root.starts_with('"') {
                serde_json::from_str::<String>(root)?
            } else {
                root.into()
            };
            if root != s(&c["profile"])
                && !pattern.is_match(&root)
                && Path::new(target)
                    .file_name()
                    .is_some_and(|x| x.to_string_lossy().contains("nixos-system-"))
            {
                protected.insert(target.into());
            }
        }
    }
    let pins = Path::new(s(&c["pinsDirectory"]));
    if pins.exists() {
        for entry in fs::read_dir(pins)? {
            let path = entry?.path();
            if path.is_symlink() {
                protected.insert(fs::canonicalize(path)?.to_string_lossy().into_owned());
            }
        }
    }
    let identities = protected
        .iter()
        .map(|v| identity(v))
        .collect::<Result<std::collections::BTreeSet<_>>>()?;
    let name = profile.file_name().ok_or("Profile name")?.to_string_lossy();
    let pattern = regex::Regex::new(&format!(r"^{}-(\d+)-link$", regex::escape(&name)))?;
    let mut generations = Vec::new();
    for entry in fs::read_dir(profile.parent().ok_or("Profile parent")?)? {
        let path = entry?.path();
        let file = path.file_name().ok_or("Generation name")?.to_string_lossy();
        if !file.starts_with(&format!("{name}-")) || !file.ends_with("-link") {
            continue;
        }
        let cap = pattern
            .captures(&file)
            .ok_or("Unexpected system generation entry")?;
        if !path.is_symlink() {
            return fail("Unexpected system generation entry");
        }
        let target = fs::canonicalize(&path)?;
        if !target.starts_with(s(&c["storeDirectory"])) {
            return fail("Generation is outside immutable store");
        }
        let m = fs::symlink_metadata(&path)?;
        generations.push(json!({"number":cap[1].parse::<u64>()?,"target":target.to_string_lossy(),"recoveryIdentity":identity(&target.to_string_lossy())?,"modified":m.mtime() as f64 + m.mtime_nsec() as f64/1e9}));
    }
    generations.sort_by_key(|x| std::cmp::Reverse(n(&x["number"])));
    let cutoff = now() - n(&c["keepDays"]) as f64 * 86400.;
    let candidates: Vec<_> = generations
        .iter()
        .skip(n(&c["keepCount"]) as usize)
        .filter(|x| {
            x["modified"].as_f64().unwrap_or(f64::INFINITY) < cutoff
                && !protected.contains(s(&x["target"]))
                && !identities.contains(s(&x["recoveryIdentity"]))
        })
        .map(|x| x["number"].clone())
        .collect();
    let mut result = json!({"profile":profile.to_string_lossy(),"generations":generations,"protectedTargets":protected,"candidates":candidates});
    result["fingerprint"] = json!(receipt_hash(&result)?);
    Ok(result)
}
fn main() {
    entry(|| {
        let a = args();
        let p = read(option(&a, "--policy").ok_or_else(|| usage_error("--policy required"))?)?;
        let command = a
            .iter()
            .find(|v| ["plan", "apply", "retire"].contains(&v.as_str()))
            .ok_or_else(|| usage_error("Choose plan/apply/retire"))?;
        let mut reviewed = plan(&p)?;
        if command == "plan" {
            save(state(&p, "generation-plan.json"), &reviewed, 0o600)?;
            println!("{reviewed}");
            return Ok(0);
        }
        if command == "apply" {
            reviewed = read(option(&a, "--plan").ok_or("Supply the exact reviewed --plan file")?)?;
        }
        let _lock = existing_lock(s(&p["bulkLock"]), false)?;
        let current = plan(&p)?;
        if current["fingerprint"] != reviewed["fingerprint"] {
            return fail("Generation plan changed; review a fresh plan");
        }
        let c = &p["generations"];
        let pins = Path::new(s(&c["pinsDirectory"]));
        fs::create_dir_all(pins)?;
        fs::set_permissions(pins, fs::Permissions::from_mode(0o700))?;
        let temporary = pins.join(".last-booted.tmp");
        if temporary.is_symlink() || temporary.exists() {
            fs::remove_file(&temporary)?;
        }
        symlink(fs::canonicalize(s(&c["bootedSystem"]))?, &temporary)?;
        fs::rename(temporary, pins.join("last-booted"))?;
        let candidates = current["candidates"].as_array().ok_or("Candidates")?;
        if !candidates.is_empty() {
            let mut a = vec![
                s(&c["nixEnv"]).into(),
                "--profile".into(),
                s(&c["profile"]).into(),
                "--delete-generations".into(),
            ];
            a.extend(candidates.iter().map(Value::to_string));
            run(&a)?;
        }
        let result = json!({"completed":now(),"plan":current,"status":"retired"});
        save(state(&p, "generation-retirement.json"), &result, 0o600)?;
        println!("{result}");
        Ok(0)
    })
}
