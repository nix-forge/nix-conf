//! Read bundle metadata, verify signing identity and inspect running applications.

use super::{array, command, command_raw, p as path_field, re, s as text_field};
use macos_application_tools::{Result, fail};
use serde_json::{Value, json};
use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    path::{Path, PathBuf},
};
use unicode_casefold::UnicodeCaseFold;

fn plist(path: &Path) -> Result<plist::Dictionary> {
    plist::Value::from_file(path.join("Contents/Info.plist"))?
        .into_dictionary()
        .ok_or_else(|| "Invalid bundle plist".into())
}
fn field(d: &plist::Dictionary, k: &str) -> String {
    d.get(k)
        .and_then(plist::Value::as_string)
        .unwrap_or("")
        .to_owned()
}
fn build_field(d: &plist::Dictionary, k: &str) -> String {
    match d.get(k) {
        Some(plist::Value::Integer(n)) => n
            .as_signed()
            .map(|v| v.to_string())
            .or_else(|| n.as_unsigned().map(|v| v.to_string()))
            .unwrap_or_default(),
        Some(plist::Value::Real(n)) => nix_conf_legacy_numbers::python_float(*n)
            .unwrap_or_else(|_| n.to_string().to_ascii_lowercase()),
        _ => field(d, k),
    }
}
pub(super) fn metadata(path: &Path) -> Result<Value> {
    let d = plist(path)?;
    let id = field(&d, "CFBundleIdentifier");
    let exe = field(&d, "CFBundleExecutable");
    if id.is_empty()
        || exe.is_empty()
        || Path::new(&exe).file_name().and_then(|x| x.to_str()) != Some(&exe)
    {
        return fail("Invalid bundle identifier or executable");
    }
    let mut build = build_field(&d, "CFBundleVersion");
    if build.is_empty() {
        build = build_field(&d, "CFBundleShortVersionString");
    }
    Ok(
        json!({"bundle":path.file_name().and_then(|s|s.to_str()).ok_or("Invalid bundle name")?,"bundleId":id,"build":build}),
    )
}
pub(super) fn signature(path: &Path, verify: bool) -> Result<Value> {
    let path = path.to_str().ok_or("Invalid bundle path")?;
    let (ok, details) =
        command_raw(&["/usr/bin/codesign", "--display", "--verbose=4", "-r-", path])?;
    if !ok {
        if !verify && details.contains("code object is not signed at all") {
            return Ok(json!({"kind":"unsigned","cdhash":null,"team":null,"requirement":null}));
        }
        return fail(&format!(
            "Cannot inspect {path}: {}",
            details
                .chars()
                .rev()
                .take(1000)
                .collect::<String>()
                .chars()
                .rev()
                .collect::<String>()
        ));
    }
    if verify {
        command(&[
            "/usr/bin/codesign",
            "--verify",
            "--deep",
            "--strict",
            "--all-architectures",
            path,
        ])?;
    }
    let fields: BTreeMap<_, _> = details
        .lines()
        .filter_map(|line| line.split_once('='))
        .collect();
    let requirement = fields
        .get("designated ")
        .or_else(|| fields.get("# designated "))
        .copied()
        .unwrap_or("")
        .trim_start_matches("> ")
        .trim();
    Ok(
        json!({"kind":if fields.get("Signature")==Some(&"adhoc") {"ad-hoc"} else {"certificate"},"identifier":fields.get("Identifier"),"format":fields.get("Format").copied().unwrap_or(""),"cdhash":fields.get("CDHash"),"team":fields.get("TeamIdentifier"),"requirement":requirement}),
    )
}
pub(super) fn inspect(path: &Path, application: &Value) -> Result<Value> {
    let d = plist(path)?;
    if field(&d, "CFBundleIdentifier") != text_field(application, "bundleId") {
        return fail("Unexpected bundle identifier");
    }
    metadata(path)?;
    command(&[
        "/usr/bin/codesign",
        "--verify",
        "--deep",
        "--strict",
        "--all-architectures",
        path.to_str().ok_or("Invalid path")?,
    ])?;
    let image = path
        .join("Contents/MacOS")
        .join(field(&d, "CFBundleExecutable"));
    let output = command(&[
        "/usr/bin/dwarfdump",
        "--uuid",
        image.to_str().ok_or("Invalid image")?,
    ])?;
    let mut uuids = vec![];
    let mut hashes = vec![];
    for c in re(r"UUID: ([A-Fa-f0-9-]+) \(([^)]+)\)").captures_iter(&output) {
        let output = command(&[
            "/usr/bin/codesign",
            "-d",
            "--verbose=4",
            "--arch",
            &c[2],
            path.to_str().ok_or("Invalid path")?,
        ])?;
        let fields: BTreeMap<_, _> = re(r"(?m)^(Identifier|TeamIdentifier|CDHash)=(.+)$")
            .captures_iter(&output)
            .map(|c| (c[1].to_owned(), c[2].to_owned()))
            .collect();
        let hash = fields
            .get("CDHash")
            .map(|s| s.to_lowercase())
            .unwrap_or_default();
        if fields.get("Identifier").map(String::as_str) != Some(text_field(application, "bundleId"))
            || fields.get("TeamIdentifier").map(String::as_str)
                != Some(text_field(application, "teamId"))
            || !re(r"^[0-9a-f]{40}$").is_match(&hash)
        {
            return fail("Unexpected signing identity");
        }
        uuids.push(c[1].to_uppercase());
        hashes.push(hash);
    }
    if uuids.is_empty() {
        return fail("No Mach-O UUID");
    }
    Ok(json!({"cdhashes":hashes,"build":build_field(&d,"CFBundleVersion"),"uuids":uuids}))
}
pub(super) fn running(manifest: &Value, application: &Value) -> Result<Value> {
    let value: Value = serde_json::from_str(&command(&[
        "/usr/bin/osascript",
        "-l",
        "JavaScript",
        text_field(manifest, "queryScript"),
        text_field(application, "bundleId"),
    ])?)?;
    let running = &value[text_field(application, "bundleId")]["running"];
    array(running)?;
    Ok(running.clone())
}
#[cfg(target_os = "macos")]
#[allow(
    unsafe_code,
    reason = "native ABI adapter with locally documented ownership and lifetimes"
)]
fn process(pid: i32) -> Result<Value> {
    #[repr(C)]
    struct Identity {
        uuid: [u8; 16],
        unique: u64,
        parent: u64,
        version: i32,
        original: i32,
        reserved2: u64,
        reserved3: u64,
    }
    #[link(name = "proc")]
    unsafe extern "C" {
        fn proc_pidinfo(
            pid: i32,
            flavor: i32,
            arg: u64,
            buffer: *mut std::ffi::c_void,
            size: i32,
        ) -> i32;
    }
    unsafe extern "C" {
        fn csops(pid: i32, op: u32, buffer: *mut std::ffi::c_void, size: usize) -> i32;
    }
    let mut info = Identity {
        uuid: [0; 16],
        unique: 0,
        parent: 0,
        version: 0,
        original: 0,
        reserved2: 0,
        reserved3: 0,
    };
    let mut hash = [0u8; 20];
    // Apple proc_uniqidentifierinfo and CS_OPS_CDHASH; compare before/after disk inspection.
    if std::mem::size_of::<Identity>() != 56
        // SAFETY: Identity has the checked ABI size and is writable for this synchronous call.
        || unsafe { proc_pidinfo(pid, 17, 0, (&mut info as *mut Identity).cast(), 56) } != 56
        // SAFETY: CS_OPS_CDHASH writes exactly the 20 bytes allocated in hash.
        || unsafe { csops(pid, 5, hash.as_mut_ptr().cast(), 20) } != 0
        || hash.iter().all(|b| *b == 0)
    {
        return fail("Cannot establish native loaded identity; Quit/reopen the canonical app");
    }
    let hex = |bytes: &[u8]| bytes.iter().map(|b| format!("{b:02X}")).collect::<String>();
    let u = hex(&info.uuid);
    Ok(json!([
        format!(
            "{}-{}-{}-{}-{}",
            &u[..8],
            &u[8..12],
            &u[12..16],
            &u[16..20],
            &u[20..]
        ),
        info.unique,
        info.version,
        hex(&hash).to_lowercase()
    ]))
}
#[cfg(not(target_os = "macos"))]
fn process(_pid: i32) -> Result<Value> {
    fail("Native loaded identity API is unavailable")
}
pub(super) fn inspect_live(
    manifest: &Value,
    application: &Value,
    path: &Path,
) -> Result<(Value, Value)> {
    let live = running(manifest, application)?;
    let mut before = BTreeMap::new();
    for item in array(&live)? {
        let pid = item["pid"]
            .as_i64()
            .and_then(|p| i32::try_from(p).ok())
            .ok_or("Invalid process PID")?;
        before.insert(pid, process(pid)?);
    }
    let disk = inspect(path, application)?;
    let mut report = vec![];
    for item in array(&live)? {
        let pid = i32::try_from(item["pid"].as_i64().ok_or("Invalid PID")?)?;
        let identity = &before[&pid];
        if path_field(item, "path") != path
            || !array(&disk["uuids"])?.contains(&identity[0])
            || !array(&disk["cdhashes"])?.contains(&identity[3])
            || process(pid)? != *identity
        {
            return fail("Running/disk identity mismatch; fully Quit and reopen canonical app");
        }
        let mut item = item.clone();
        item["identity"] = identity.clone();
        report.push(item);
    }
    if running(manifest, application)? != live {
        return fail("Application lifecycle changed during inspection; retry");
    }
    Ok((disk, json!(report)))
}
pub(super) fn upgrade(old: &Value, new: &Value) -> Result<()> {
    if old == new {
        return Ok(());
    }
    let pattern = re(r"^[0-9]+(?:\.[0-9]+)*$");
    if !pattern.is_match(text_field(old, "build")) || !pattern.is_match(text_field(new, "build")) {
        return fail("Cannot order application builds; refusing an unverified replacement");
    }
    // Decimal components are compared without an integer-width bound.
    let parts = |s: &str| {
        s.split('.')
            .map(|x| {
                let x = x.trim_start_matches('0');
                (x.len(), x.to_owned())
            })
            .collect::<Vec<_>>()
    };
    if parts(text_field(new, "build")) < parts(text_field(old, "build")) {
        return fail("Refusing app downgrade; update the Nix package selection");
    }
    Ok(())
}
pub(super) fn previous(application: &Value, dir: &Path) -> Result<Vec<PathBuf>> {
    let mut names = BTreeSet::from([text_field(application, "bundle")
        .case_fold()
        .collect::<String>()]);
    let mut paths = vec![];
    if let Some(items) = application.get("previousBundles") {
        for name in array(items)? {
            let name = name.as_str().ok_or("Invalid previous name")?;
            if !bundle_name(name) || !names.insert(name.case_fold().collect()) {
                return fail("Invalid or ambiguous previous application bundle names");
            }
            paths.push(dir.join(name));
        }
    }
    Ok(paths)
}
pub(super) fn previous_identities(
    manifest: &Value,
    application: &Value,
    dir: &Path,
    source: &Value,
) -> Result<BTreeMap<PathBuf, Value>> {
    let mut found = BTreeMap::new();
    for path in previous(application, dir)? {
        if path.is_symlink() {
            return fail("Previous app must be a real copied bundle");
        }
        if path.exists() {
            let disk = inspect(&path, application)?;
            upgrade(&disk, source)?;
            found.insert(path, disk);
        }
    }
    if !found.is_empty() && !array(&running(manifest, application)?)?.is_empty() {
        return fail("Quit application before migrating its canonical pathname");
    }
    Ok(found)
}
pub(super) fn preflight(manifest: &Value, application: &Value) -> Result<(Value, Value)> {
    let source = inspect(&path_field(application, "source"), application)?;
    let target = path_field(manifest, "appsDirectory").join(text_field(application, "bundle"));
    previous_identities(
        manifest,
        application,
        target.parent().ok_or("Missing parent")?,
        &source,
    )?;
    if target.is_symlink() {
        return fail("Protected app must be a real copied bundle");
    }
    if !target.exists() {
        if !array(&running(manifest, application)?)?.is_empty() {
            return fail("Protected app is running from another path; Quit it first");
        }
        return Ok((source, Value::Null));
    }
    let (disk, live) = inspect_live(manifest, application, &target)?;
    if disk != source {
        if !array(&live)?.is_empty() {
            return fail("Quit application before activating update; installed app left intact");
        }
        upgrade(&disk, &source)?;
    }
    Ok((source, disk))
}
pub(super) fn selected(manifest: &Value) -> Result<Vec<Value>> {
    let mut explicit = BTreeSet::new();
    let mut ids = BTreeSet::new();
    for application in array(&manifest["apps"])? {
        explicit.insert(
            text_field(application, "bundle")
                .case_fold()
                .collect::<String>(),
        );
        if let Some(n) = path_field(application, "source")
            .file_name()
            .and_then(|n| n.to_str())
        {
            explicit.insert(n.case_fold().collect());
        }
        for path in previous(application, Path::new("/"))? {
            explicit.insert(
                path.file_name()
                    .ok_or("Invalid name")?
                    .to_string_lossy()
                    .case_fold()
                    .collect(),
            );
        }
        ids.insert(text_field(application, "bundleId").to_owned());
    }
    let explicit_ids = ids.clone();
    let mut out = vec![];
    let directory = path_field(manifest, "selectedApplications");
    if !directory.exists() {
        return Ok(out);
    }
    let mut entries = fs::read_dir(directory)?.collect::<std::io::Result<Vec<_>>>()?;
    entries.sort_by_key(|e| e.file_name());
    for entry in entries {
        let name = entry
            .file_name()
            .into_string()
            .map_err(|_| "Invalid bundle name")?;
        if !name.ends_with(".app") || explicit.contains(&name.case_fold().collect::<String>()) {
            continue;
        }
        let source = fs::canonicalize(entry.path())?;
        if !source.starts_with("/nix/store") || !source.is_dir() {
            return fail("Selected application is not an immutable Nix-store bundle");
        }
        let mut application = metadata(&source)?;
        let id = text_field(&application, "bundleId").to_owned();
        if explicit_ids.contains(&id) {
            continue;
        }
        if !ids.insert(id) {
            return fail("Duplicate selected application identifier");
        }
        application["bundle"] = json!(name);
        application["source"] = json!(source);
        out.push(application);
    }
    Ok(out)
}
pub(super) fn inventory(manifest: &Value) -> Result<Value> {
    let mut results = vec![];
    for application in array(&manifest["apps"])?
        .iter()
        .cloned()
        .chain(selected(manifest)?)
    {
        let result = (|| -> Result<Value> {
            let mut found = signature(&path_field(&application, "source"), false)?;
            if text_field(&found, "kind") == "certificate" {
                found = signature(&path_field(&application, "source"), true)?;
            }
            Ok(
                json!({"bundle":application["bundle"],"policy":if text_field(&found,"kind")=="certificate"{"preserve-certificate"}else{"local-certificate"},"identity":found}),
            )
        })();
        results.push(match result {
            Ok(v) => v,
            Err(e) => json!({"bundle":application["bundle"],"error":e.to_string()}),
        });
    }
    Ok(
        json!({"status":if results.iter().any(|v|v.get("error").is_some()){"blocked"}else{"ok"},"apps":results,"authorization":"unknown"}),
    )
}
pub(super) fn bundle_name(s: &str) -> bool {
    s.ends_with(".app") && !s.contains('/') && s.len() > 4
}
