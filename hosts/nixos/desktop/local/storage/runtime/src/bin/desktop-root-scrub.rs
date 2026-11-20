use desktop_storage_runtime::*;
use serde_json::{Value, json};
use std::{fs, io::Write, os::unix::fs::OpenOptionsExt, path::Path, time::Duration};
const GIB: u64 = 1024 * 1024 * 1024;
fn swaps() -> Result<Vec<Value>> {
    fs::read_to_string("/proc/swaps")?.lines().skip(1).map(|line|{let f:Vec<_>=line.split_whitespace().collect();if f.len()<4{return fail("Malformed swap state");}Ok(json!({"name":f[0],"kind":f[1],"size":f[2].parse::<u64>()?*1024,"used":f[3].parse::<u64>()?*1024}))}).collect()
}
fn memory() -> Result<u64> {
    let text = fs::read_to_string("/proc/meminfo")?;
    Ok(text
        .lines()
        .find(|l| l.starts_with("MemAvailable:"))
        .and_then(|l| l.split_whitespace().nth(1))
        .ok_or("MemAvailable missing")?
        .parse::<u64>()?
        * 1024)
}
fn disk(entries: &[Value], swapfile: &str) -> u64 {
    entries
        .iter()
        .filter(|v| s(&v["name"]) != swapfile && !s(&v["name"]).starts_with("/dev/zram"))
        .map(|v| n(&v["size"]).saturating_sub(n(&v["used"])))
        .sum()
}
fn recover(p: &Value) -> Result<()> {
    let journal = state(p, "root-scrub-operation.json");
    if !journal.exists() {
        return Ok(());
    }
    let record = read(&journal)?;
    if !record["active"].is_boolean()
        || s(&record["guard"]).is_empty()
        || s(&record["body"]).is_empty()
    {
        return fail("Malformed scrub recovery journal; inspect before recovery");
    }
    if record["started"] == true {
        let out = output(
            &["btrfs".into(), "scrub".into(), "cancel".into(), "/".into()],
            30,
            None,
        )?;
        if !matches!(out.status.code(), Some(0 | 2)) {
            return fail("Could not cancel owned scrub before swap recovery");
        }
    }
    let guard = Path::new(s(&record["guard"]));
    if guard.exists() || guard.is_symlink() {
        if guard.is_symlink() || fs::read_to_string(guard)? != s(&record["body"]) {
            return fail("Root scrub activation guard changed; inspect before recovery");
        }
        fs::remove_file(guard)?;
    }
    cmd(&["systemctl", "daemon-reload"])?;
    if record["active"] == true {
        cmd(&["systemctl", "start", s(&p["swapUnit"])])?;
        if !swaps()?.iter().any(|v| v["name"] == p["swapfile"]) {
            return fail("Fallback swap did not resume");
        }
    }
    fs::remove_file(journal)?;
    Ok(())
}
fn run_scrub(p: &Value, journal: &Path) -> Result<f64> {
    let started = now();
    let mut record = read(journal)?;
    record["started"] = json!(true);
    save(journal, &record, 0o600)?;
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?;
    rt.block_on(async{use tokio::signal::unix::{signal,SignalKind};let mut term=signal(SignalKind::terminate())?;let mut int=signal(SignalKind::interrupt())?;let mut child=tokio::process::Command::new("btrfs").args(["scrub","start","-B","--limit","800M","/"]).kill_on_drop(true).spawn()?;let deadline=tokio::time::sleep(Duration::from_secs(86400));tokio::pin!(deadline);let result=loop{tokio::select!{status=child.wait()=>break if status?.success(){Ok(())}else{fail("Root scrub reported integrity or execution failure")},_=term.recv()=>break fail("Root scrub interrupted"),_=int.recv()=>break fail("Root scrub interrupted"),_=&mut deadline=>break fail("Root scrub deadline exceeded"),_=tokio::time::sleep(Duration::from_secs(30))=>{ // MemAvailable has no threshold event; bounded samples supplement child exit observation.
if memory()?<3*GIB||disk(&swaps()?,s(&p["swapfile"]))<2*GIB{break fail("Root scrub cancelled to restore memory headroom");}}}};if result.is_err(){let cancellation=tokio::process::Command::new("btrfs").args(["scrub","cancel","/"]).status().await;let _kill_result = child.kill().await;let _wait_result = child.wait().await;cancellation?;}result})?;
    if swaps()?.iter().any(|v| v["kind"] == "file") {
        return fail("Swapfile activated during scrub; coverage cannot be certified");
    }
    record["started"] = json!(false);
    save(journal, &record, 0o600)?;
    Ok(started)
}
fn scrub(p: &Value) -> Result<()> {
    fs::create_dir_all(state(p, ""))?;
    let journal = state(p, "root-scrub-operation.json");
    let guarddir = if s(&p["guardDirectory"]).is_empty() {
        "/run/systemd/system.control"
    } else {
        s(&p["guardDirectory"])
    };
    let guard = Path::new(guarddir).join(format!(
        "{}.d/90-desktop-root-scrub.conf",
        s(&p["swapUnit"])
    ));
    let _lock = lock(s(&p["bulkLock"]), false)?;
    if journal.exists() || guard.exists() || guard.is_symlink() {
        return fail("Earlier scrub needs recovery");
    }
    let entries = swaps()?;
    let files: Vec<_> = entries.iter().filter(|v| v["kind"] == "file").collect();
    if files.iter().any(|v| v["name"] != p["swapfile"]) {
        return fail("Additional swapfiles prevent full root coverage");
    }
    let used: u64 = files.iter().map(|v| n(&v["used"])).sum();
    if memory()? < used + 6 * GIB || disk(&entries, s(&p["swapfile"])) < 8 * GIB {
        return fail(
            "Root scrub needs six GiB drain RAM margin and eight GiB other disk swap free",
        );
    }
    let observation = output(
        &["btrfs".into(), "scrub".into(), "status".into(), "/".into()],
        30,
        None,
    )?;
    let status = String::from_utf8(observation.stdout)?;
    let errors = String::from_utf8(observation.stderr)?;
    if !observation.status.success()
        && !(status.clone() + &errors)
            .to_lowercase()
            .contains("no stats available")
    {
        return fail("Existing root scrub state could not be inspected");
    }
    if regex::Regex::new(r"(?m)^Status:\s+running\b")?.is_match(&status) {
        return fail("Root scrub already running outside this operation");
    }
    let body = format!("[Unit]\nConditionPathExists=!{}\n", journal.display());
    save(
        &journal,
        &json!({"active":entries.iter().any(|v|v["name"]==p["swapfile"]),"guard":guard.to_string_lossy(),"body":body}),
        0o600,
    )?;
    let operation = (|| -> Result<f64> {
        fs::create_dir_all(guard.parent().ok_or("Guard parent")?)?;
        fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&guard)?
            .write_all(body.as_bytes())?;
        cmd(&["systemctl", "daemon-reload"])?;
        if entries.iter().any(|v| v["name"] == p["swapfile"]) {
            cmd(&["systemctl", "stop", s(&p["swapUnit"])])?;
        }
        if swaps()?.iter().any(|v| v["kind"] == "file") {
            return fail("Swapfile remains active; refusing incomplete scrub");
        }
        run_scrub(p, &journal)
    })();
    let recovery = recover(p);
    let started = operation?;
    recovery?;
    save(
        state(p, "checks/root-scrub.json"),
        &json!({"completed":now(),"started":started,"result":"success","scope":"root-without-active-swapfiles"}),
        0o644,
    )
}
fn main() {
    entry(|| {
        let a = args();
        let p = read(a.first().ok_or_else(|| usage_error("Policy required"))?)?;
        match a.get(1).map(String::as_str) {
            Some("run") => scrub(&p)?,
            Some("recover") => recover(&p)?,
            _ => return usage("Choose run/recover"),
        };
        Ok(0)
    })
}
