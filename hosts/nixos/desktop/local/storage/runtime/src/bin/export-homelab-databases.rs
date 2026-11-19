use desktop_storage_runtime::*;
use serde_json::{Value, json};
use std::{
    fs,
    os::unix::fs::{OpenOptionsExt, PermissionsExt},
    path::Path,
};
fn safe(v: &str) -> bool {
    !v.is_empty()
        && v.bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}
fn pg(c: &Value, tool: &str, extra: Vec<String>) -> Vec<String> {
    let mut a = list(&c["commandPrefix"]);
    a.push(format!("{}/bin/{tool}", s(&c["package"])));
    a.push(format!("--host={}", s(&c["socket"])));
    a.push(format!("--username={}", s(&c["user"])));
    a.extend(extra);
    a
}
fn dump(a: &[String], path: &Path) -> Result<()> {
    let file = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(path)?;
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?;
    rt.block_on(async{use tokio::{io::AsyncReadExt,signal::unix::{signal,SignalKind}};let mut term=signal(SignalKind::terminate())?;let mut int=signal(SignalKind::interrupt())?;let mut c=tokio::process::Command::new(a.first().ok_or("Empty dump command")?).args(&a[1..]).stdout(file).stderr(std::process::Stdio::piped()).process_group(0).kill_on_drop(true).spawn()?;let pid=c.id().and_then(|p|rustix::process::Pid::from_raw(p as i32));let mut stderr=c.stderr.take().ok_or("Missing stderr")?;let mut buffer=Vec::new();let result={let work=async{tokio::try_join!(stderr.read_to_end(&mut buffer),c.wait()).map(|(_,s)|s)};tokio::select!{r=tokio::time::timeout(std::time::Duration::from_secs(7200),work)=>match r{Ok(Ok(s)) if s.success()=>Ok(()),_=>fail("Database dump failed or exceeded deadline")},_=term.recv()=>fail("Database dump interrupted"),_=int.recv()=>fail("Database dump interrupted")}};if result.is_err(){if let Some(pid)=pid{let _signal_result = rustix::process::kill_process_group(pid,rustix::process::Signal::KILL);}let _kill_result = c.kill().await;let _wait_result = c.wait().await;}result})
}
fn export(p: &Value) -> Result<Value> {
    let root = Path::new(s(&p["directory"]));
    fs::create_dir_all(root)?;
    fs::set_permissions(root, fs::Permissions::from_mode(0o700))?;
    let staging = tempfile::Builder::new()
        .prefix("pending-")
        .tempdir_in(root)?;
    let mut records = Vec::new();
    for e in p["sqlite"].as_array().ok_or("SQLite policy")? {
        let name = s(&e["name"]);
        if !safe(name) {
            return fail("Unsafe export name");
        }
        let source = Path::new(s(&e["path"]));
        if !source.is_file() {
            if e["optional"] == true {
                records.push(json!({"name":name,"kind":"sqlite","absent":true}));
                continue;
            }
            return fail("Required database is absent");
        }
        let source = fs::canonicalize(source)?;
        let target = staging.path().join(format!("{name}.sqlite"));
        let quoted = json!(target.to_string_lossy()).to_string();
        let result = output(
            &[
                "sqlite3".into(),
                "-readonly".into(),
                source.to_string_lossy().into_owned(),
            ],
            7200,
            Some(format!(".timeout 30000\n.backup {quoted}\n").as_bytes()),
        )?;
        if !result.status.success() {
            return fail("SQLite online backup failed");
        }
        if cmd(&[
            "sqlite3",
            "-readonly",
            &target.to_string_lossy(),
            "PRAGMA quick_check;",
        ])?
        .trim()
            != "ok"
        {
            return fail("SQLite copy failed validation");
        }
        let mut record = fingerprint(&target)?;
        record["name"] = json!(name);
        record["kind"] = json!("sqlite");
        records.push(record);
    }
    for c in p["postgresql"].as_array().ok_or("PostgreSQL policy")? {
        let cluster = s(&c["name"]);
        if !safe(cluster) {
            return fail("Unsafe cluster name");
        }
        let a=pg(c,"psql",vec!["-XAt".into(),"--set=ON_ERROR_STOP=1".into(),"--dbname=postgres".into(),"--command=SELECT coalesce(json_agg(datname ORDER BY datname), '[]')::text FROM pg_database WHERE datallowconn AND NOT datistemplate".into()]);
        let names: Value = serde_json::from_str(&run(&a)?)?;
        let mut exports = vec![(
            "globals".to_owned(),
            "pg_dumpall",
            vec!["--globals-only".into()],
            ".sql",
        )];
        for name in names.as_array().ok_or("Malformed database discovery")? {
            let name = name.as_str().ok_or("Malformed database name")?;
            if !safe(name) {
                return fail("PostgreSQL discovery returned unsafe database name");
            }
            exports.push((
                name.into(),
                "pg_dump",
                vec!["--format=custom".into(), format!("--dbname={name}")],
                ".dump",
            ));
        }
        for (name, tool, extra, suffix) in exports {
            let target = staging.path().join(format!("{cluster}-{name}{suffix}"));
            dump(&pg(c, tool, extra), &target)?;
            let mut record = fingerprint(&target)?;
            record["name"] = json!(name);
            record["cluster"] = json!(cluster);
            record["kind"] = json!("postgresql");
            records.push(record);
        }
    }
    let ns = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)?
        .as_nanos();
    let ns = u64::try_from(ns)?;
    let manifest =
        json!({"format":"homelab-database-backup/v1","createdNs":ns,"databases":records});
    save(staging.path().join("manifest.json"), &manifest, 0o600)?;
    let generation = root.join(format!("generation-{ns}"));
    fs::rename(staging.path(), &generation)?;
    save(
        root.join("latest.json"),
        &json!({"generation":generation.file_name().ok_or("Generation name")?.to_string_lossy(),"createdNs":ns}),
        0o600,
    )?;
    let mut generations = fs::read_dir(root)?
        .map(|e| e.map(|e| e.path()))
        .collect::<std::io::Result<Vec<_>>>()?;
    generations.retain(|p| {
        p.file_name()
            .is_some_and(|n| n.to_string_lossy().starts_with("generation-"))
    });
    generations.sort();
    let count = generations.len().saturating_sub(2);
    for path in generations.into_iter().take(count) {
        if !path.is_symlink()
            && path.is_dir()
            && read(path.join("manifest.json"))?["format"] == "homelab-database-backup/v1"
        {
            fs::remove_dir_all(path)?;
        }
    }
    Ok(manifest)
}
fn main() {
    entry(|| {
        rustix::process::umask(rustix::fs::Mode::from_raw_mode(0o077));
        let p = read(
            args()
                .first()
                .ok_or_else(|| usage_error("Policy required"))?,
        )?;
        let manifest = export(&p)?;
        println!(
            "Published consistent database exports: {}",
            manifest["databases"].as_array().ok_or("Manifest")?.len()
        );
        Ok(0)
    })
}
