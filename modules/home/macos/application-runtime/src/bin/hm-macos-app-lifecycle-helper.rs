//! Transactional copied-application lifecycle. Privacy authorization is never inferred.
use clap::Parser;
use macos_application_tools::{Result, fail};
use serde_json::{Value as V, json};
use sha2::{Digest, Sha256};
use std::{
    collections::{BTreeMap, BTreeSet},
    fs::{self, File},
    io::Read,
    path::{Path, PathBuf},
    time::Duration,
};
use unicode_casefold::UnicodeCaseFold;

#[path = "lifecycle/inspection.rs"]
mod inspection;
#[path = "lifecycle/state.rs"]
mod state;

use inspection::{
    bundle_name, inspect, inspect_live, inventory, metadata, preflight, previous,
    previous_identities, running, selected, signature, upgrade,
};
use state::{atomic, check_state, journal, lock, read_private, record_path, save};

const LS: &str = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister";
#[derive(Parser)]
struct Args {
    #[arg(long)]
    manifest: PathBuf,
    #[arg(long, default_value="check", value_parser=["inventory","enroll-identity","preflight","install","check","refresh","refresh-system","observe"])]
    mode: String,
    #[arg(long)]
    if_changed: bool,
}
fn s<'a>(v: &'a V, key: &str) -> &'a str {
    v[key].as_str().unwrap_or("")
}
fn p(v: &V, key: &str) -> PathBuf {
    PathBuf::from(s(v, key))
}
fn array(v: &V) -> Result<&Vec<V>> {
    v.as_array()
        .ok_or_else(|| "Expected application array".into())
}
fn re(pattern: &str) -> regex::Regex {
    regex::Regex::new(pattern).unwrap_or_else(|_| unreachable!())
}
fn command_raw(args: &[&str]) -> Result<(bool, String)> {
    let timeout = if args[0] == "/usr/bin/codesign" {
        120
    } else if args.starts_with(&["/bin/launchctl", "asuser"])
        && args.ends_with(&["--mode", "check"])
    {
        900
    } else {
        30
    };
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?;
    let output = rt.block_on(nix_conf_process::run(
        tokio::process::Command::new(args[0]).args(&args[1..]),
        None,
        Duration::from_secs(timeout),
    ))?;
    Ok((
        output.status.success(),
        format!(
            "{}{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        ),
    ))
}
fn command(args: &[&str]) -> Result<String> {
    let (ok, out) = command_raw(args)?;
    if !ok {
        return fail(&format!(
            "{}: {}",
            args[0],
            out.chars().take(1000).collect::<String>()
        ));
    }
    Ok(out)
}
fn run_owned(args: &[String]) -> Result<String> {
    command(&args.iter().map(String::as_str).collect::<Vec<_>>())
}
fn copy(m: &V, source: &Path, dest: &Path) -> Result<()> {
    fs::create_dir(dest)?;
    command(&[
        s(m, "rsync"),
        "--recursive",
        "--checksum",
        "--perms",
        "--links",
        "--copy-unsafe-links",
        "--specials",
        "--chmod=+w",
        &format!("{}/", source.display()),
        &format!("{}/", dest.display()),
    ])?;
    Ok(())
}
#[cfg(target_os = "macos")]
#[allow(
    unsafe_code,
    reason = "native ABI adapter with locally documented ownership and lifetimes"
)]
fn rename(source: &Path, dest: &Path, exchange: bool) -> Result<()> {
    use std::{ffi::CString, os::unix::ffi::OsStrExt};
    unsafe extern "C" {
        fn renameatx_np(
            a: i32,
            s: *const std::ffi::c_char,
            b: i32,
            d: *const std::ffi::c_char,
            flags: u32,
        ) -> i32;
    }
    let a = CString::new(source.as_os_str().as_bytes())?;
    let b = CString::new(dest.as_os_str().as_bytes())?;
    // SAFETY: both paths are live CStrings; AT_FDCWD and flags match Darwin renameatx_np.
    if unsafe { renameatx_np(-2, a.as_ptr(), -2, b.as_ptr(), if exchange { 2 } else { 4 }) } != 0 {
        return Err(std::io::Error::last_os_error().into());
    }
    for parent in [source.parent(), dest.parent()].into_iter().flatten() {
        File::open(parent)?.sync_all()?;
    }
    Ok(())
}
#[cfg(not(target_os = "macos"))]
fn rename(_source: &Path, _dest: &Path, _exchange: bool) -> Result<()> {
    fail("Atomic app exchange requires Darwin")
}
fn swap(source: &Path, dest: &Path) -> Result<()> {
    rename(source, dest, dest.exists())
}
fn register(path: &Path) -> Result<()> {
    command(&[LS, "-f", path.to_str().ok_or("Invalid path")?])?;
    Ok(())
}
fn registered(m: &V, a: &V, prefix: &[String]) -> Result<BTreeSet<PathBuf>> {
    let mut args = prefix.to_vec();
    args.extend(
        [
            s(m, "registryHelper"),
            "--query-script",
            s(m, "queryScript"),
            "--registered-paths",
            s(a, "bundleId"),
        ]
        .map(str::to_owned),
    );
    let v: V = serde_json::from_str(&run_owned(&args)?)?;
    let mut paths = BTreeSet::new();
    for path in array(&v[s(a, "bundleId")])? {
        let text = path
            .as_str()
            .ok_or("Invalid native registration inventory")?;
        let path = PathBuf::from(text);
        if !canonical_path(text) {
            return fail("Noncanonical native registration path");
        }
        paths.insert(path);
    }
    Ok(paths)
}
fn unregister(m: &V, a: &V, path: &Path, prefix: &[String]) -> Result<()> {
    if !registered(m, a, prefix)?.contains(path) {
        return Ok(());
    }
    let mut args = prefix.to_vec();
    args.extend([
        LS.to_owned(),
        "-u".to_owned(),
        path.to_str().ok_or("Invalid path")?.to_owned(),
    ]);
    run_owned(&args)?;
    if registered(m, a, prefix)?.contains(path) {
        return fail("Application registration remains eligible after retirement");
    }
    Ok(())
}
fn transaction() -> tempfile::Builder<'static, 'static> {
    let mut b = tempfile::Builder::new();
    b.prefix(".hm-app-update-").suffix(".noindex");
    b
}
fn protected_install(m: &V, a: &V) -> Result<String> {
    let (source, disk) = preflight(m, a)?;
    let dir = p(m, "appsDirectory");
    let previous = previous_identities(m, a, &dir, &source)?;
    if source == disk && previous.is_empty() {
        return Ok("unchanged".into());
    }
    let temp = transaction().tempdir_in(dir.parent().ok_or("Missing app parent")?)?;
    let directory = temp.path().to_owned();
    let staged = directory.join(s(a, "bundle"));
    let target = dir.join(s(a, "bundle"));
    let evidence = json!({"canonical":target,"selectedSource":a["source"],"sourceIdentity":source,"previous":previous.iter().map(|(p,v)|(p.to_string_lossy().to_string(),v.clone())).collect::<BTreeMap<_,_>>()});
    // Disarm cleanup before the first mutation intent. OOM/kill leaves complete bundles and durable journal.
    let mut temp = Some(temp);
    let mut retained = false;
    let result = (|| -> Result<()> {
        if source != disk {
            copy(m, &p(a, "source"), &staged)?;
            if inspect(&staged, a)? != source {
                return fail("Staged signature differs from selected package");
            }
        }
        if preflight(m, a)? != (source.clone(), disk.clone())
            || previous_identities(m, a, &dir, &source)? != previous
        {
            return fail("Application changed while staging; original retained");
        }
        if source != disk {
            if let Some(t) = temp.take() {
                let _retained_path = t.keep();
            }
            retained = true;
            journal(&directory, "install-intent", &evidence)?;
            swap(&staged, &target)?;
            if !disk.is_null() {
                if inspect(&staged, a)? != disk {
                    return fail("Retained prior application identity changed");
                }
                unregister(m, a, &staged, &[])?;
            }
            journal(&directory, "installed", &evidence)?;
        }
        for (path, identity) in &previous {
            if !array(&running(m, a)?)?.is_empty()
                || path.is_symlink()
                || inspect(path, a)? != *identity
            {
                return fail("Previous application changed during migration");
            }
            if let Some(t) = temp.take() {
                let _retained_path = t.keep();
            }
            retained = true;
            let mut e = evidence.clone();
            e["retiring"] = json!(path);
            journal(&directory, "retire-intent", &e)?;
            let backup = directory.join(path.file_name().ok_or("Invalid previous path")?);
            rename(path, &backup, false)?;
            if inspect(&backup, a)? != *identity {
                return fail("Retained previous identity changed");
            }
            unregister(m, a, path, &[])?;
            unregister(m, a, &backup, &[])?;
            e["retired"] = json!(path);
            e.as_object_mut()
                .ok_or("Invalid journal")?
                .remove("retiring");
            journal(&directory, "retired", &e)?;
        }
        register(&target)?;
        journal(&directory, "registered-user", &evidence)?;
        Ok(())
    })();
    if let Err(e) = result {
        if retained {
            return fail(&format!(
                "{e}; complete bundles and journal retained in {}",
                directory.display()
            ));
        }
        return Err(e);
    }
    Ok(format!(
        "installed; previous bundle retained in {}",
        directory.display()
    ))
}
fn enrolled(m: &V) -> Result<V> {
    let policy = &m["localSigning"];
    let identity = read_private(&p(m, "stateDirectory").join("signing-identity.json"))?;
    if identity.is_null() {
        return fail(
            "Create a persistent Code Signing identity in Keychain Access, then run hm-macos-app-lifecycle --mode enroll-identity; no key was generated",
        );
    }
    if identity["name"] != policy["identity"] || identity["keychain"] != policy["keychain"] {
        return fail("Enrolled signing identity differs from configured policy");
    }
    if !s(policy, "certificateSha256").is_empty()
        && s(&identity, "sha256") != s(policy, "certificateSha256").to_lowercase()
    {
        return fail("Enrolled signing certificate does not match Nix fingerprint");
    }
    if !re(r"^[a-f0-9]{40}$").is_match(s(&identity, "sha1"))
        || !re(r"^[a-f0-9]{64}$").is_match(s(&identity, "sha256"))
    {
        return fail("Invalid enrolled signing certificate fingerprints");
    }
    Ok(identity)
}
fn enroll(m: &V) -> Result<V> {
    use base64::Engine;
    let policy = &m["localSigning"];
    let pem = command(&[
        "/usr/bin/security",
        "find-certificate",
        "-a",
        "-c",
        s(policy, "identity"),
        "-p",
        s(policy, "keychain"),
    ])?;
    let available = command(&[
        "/usr/bin/security",
        "find-identity",
        "-p",
        "codesigning",
        s(policy, "keychain"),
    ])?;
    let pattern = re(&format!(
        r#"\b([A-Fa-f0-9]{{40}}) "{}""#,
        regex::escape(s(policy, "identity"))
    ));
    let matches: BTreeSet<_> = pattern
        .captures_iter(&available)
        .map(|c| c[1].to_owned())
        .collect();
    if matches.len() != 1 {
        return fail("Expected exactly one Code Signing identity with configured name");
    }
    let digest = matches.first().ok_or("Missing identity")?.to_lowercase();
    let mut candidates = vec![];
    for c in re(r"(?s)-----BEGIN CERTIFICATE-----\s*(.*?)\s*-----END CERTIFICATE-----")
        .captures_iter(&pem)
    {
        let bytes = base64::engine::general_purpose::STANDARD
            .decode(c[1].split_whitespace().collect::<String>())?;
        if format!("{:x}", sha1::Sha1::digest(&bytes)) == digest {
            candidates.push(bytes);
        }
    }
    if candidates.len() != 1 {
        return fail("Could not uniquely match signing certificate to private key identity");
    }
    let identity = json!({"name":policy["identity"],"keychain":policy["keychain"],"sha1":digest,"sha256":format!("{:x}",Sha256::digest(&candidates[0]))});
    if !s(policy, "certificateSha256").is_empty()
        && s(policy, "certificateSha256").to_lowercase() != s(&identity, "sha256")
    {
        return fail("Keychain certificate does not match Nix fingerprint");
    }
    let state = p(m, "stateDirectory");
    let _lock = lock(&state)?;
    let path = state.join("signing-identity.json");
    let old = read_private(&path)?;
    if !old.is_null() && old != identity {
        return fail(
            "A different signing identity is already enrolled; explicit migration required",
        );
    }
    save(&path, &identity)?;
    Ok(json!({"status":"ok","identity":identity,"authorization":"unknown"}))
}
fn verify_certificate(path: &Path, identity: &V) -> Result<()> {
    let dir = tempfile::Builder::new()
        .prefix("hm-app-certificate-")
        .tempdir()?;
    let prefix = dir.path().join("cert");
    command(&[
        "/usr/bin/codesign",
        "--display",
        "--extract-certificates",
        prefix.to_str().ok_or("Invalid path")?,
        path.to_str().ok_or("Invalid path")?,
    ])?;
    if format!("{:x}", Sha256::digest(fs::read(dir.path().join("cert0"))?)) != s(identity, "sha256")
    {
        return fail("Unexpected local signing certificate");
    }
    Ok(())
}
fn nested_code(path: &Path, out: &mut Vec<PathBuf>) -> Result<()> {
    for entry in fs::read_dir(path)? {
        let entry = entry?;
        let p = entry.path();
        let kind = entry.file_type()?;
        if kind.is_symlink() {
            continue;
        }
        if kind.is_dir() {
            if matches!(
                p.extension().and_then(|e| e.to_str()),
                Some("app" | "framework" | "xpc" | "appex" | "bundle")
            ) {
                out.push(p.clone());
            }
            nested_code(&p, out)?;
        } else if kind.is_file() {
            let mut magic = [0u8; 4];
            let n = File::open(&p)?.read(&mut magic)?;
            if n == 4
                && matches!(
                    magic,
                    [0xfe, 0xed, 0xfa, 0xce]
                        | [0xce, 0xfa, 0xed, 0xfe]
                        | [0xfe, 0xed, 0xfa, 0xcf]
                        | [0xcf, 0xfa, 0xed, 0xfe]
                        | [0xca, 0xfe, 0xba, 0xbe]
                        | [0xbe, 0xba, 0xfe, 0xca]
                        | [0xca, 0xfe, 0xba, 0xbf]
                        | [0xbf, 0xba, 0xfe, 0xca]
                )
            {
                out.push(p);
            }
        }
    }
    Ok(())
}
fn sign(path: &Path, identity: &V) -> Result<()> {
    let available = command(&[
        "/usr/bin/security",
        "find-identity",
        "-p",
        "codesigning",
        s(identity, "keychain"),
    ])?;
    if !available
        .to_uppercase()
        .contains(&s(identity, "sha1").to_uppercase())
    {
        return fail(
            "Enrolled signing key is unavailable or locked; installed applications retained",
        );
    }
    let mut nested = vec![];
    nested_code(path, &mut nested)?;
    nested.sort_by_key(|p| std::cmp::Reverse(p.components().count()));
    nested.push(path.to_owned());
    for candidate in nested {
        let existing = signature(&candidate, false)?;
        let mut args = vec![
            "/usr/bin/codesign",
            "--force",
            "--sign",
            s(identity, "sha1"),
            "--keychain",
            s(identity, "keychain"),
            "--timestamp=none",
        ];
        if s(&existing, "kind") != "unsigned" {
            args.push("--preserve-metadata=entitlements,flags");
        }
        let meta = metadata(path)?;
        if candidate == path {
            args.extend(["--identifier", s(&meta, "bundleId")]);
        }
        args.push(candidate.to_str().ok_or("Invalid path")?);
        command(&args)?;
    }
    signature(path, true)?;
    verify_certificate(path, identity)
}
fn managed_plan(m: &V, a: &V) -> Result<V> {
    let mut source = signature(&p(a, "source"), false)?;
    if s(&source, "kind") == "certificate" {
        source = signature(&p(a, "source"), true)?;
    }
    let target = p(m, "appsDirectory").join(s(a, "bundle"));
    if target.is_symlink() {
        return fail("Managed application must be a real directory");
    }
    let mut disk = if target.exists() {
        signature(&target, false)?
    } else {
        V::Null
    };
    if s(&disk, "kind") == "certificate" {
        disk = signature(&target, true)?;
    }
    if !disk.is_null() && metadata(&target)?["bundleId"] != a["bundleId"] {
        return fail("Refusing to replace a different application");
    }
    let record = read_private(&record_path(&p(m, "stateDirectory"), s(a, "bundle")))?;
    if !record.is_null() && (!record["selection"].is_object() || !record["installed"].is_object()) {
        return fail("Malformed application installation record; inspect private recovery state");
    }
    let local = s(&source, "kind") != "certificate";
    let identity = if local { enrolled(m)? } else { V::Null };
    let selection = json!({"source":a["source"],"bundle":a["bundle"],"sourceIdentity":source,"bundleId":a["bundleId"],"signer":identity});
    let current = (!record.is_null()
        && record["selection"] == selection
        && record["installed"] == disk
        && !disk.is_null())
        || (!local && disk == source);
    if current && !identity.is_null() {
        verify_certificate(&target, &identity)?;
    }
    let live = running(m, a)?;
    if current && !array(&live)?.is_empty() {
        if s(&disk, "format").contains("Mach-O") {
            let mut app = a.clone();
            app["teamId"] = disk["team"].clone();
            inspect_live(m, &app, &target)?;
        } else if array(&live)?.iter().any(|item| p(item, "path") != target) {
            return fail("Running from a noncanonical application path");
        }
    }
    if !current {
        if !array(&live)?.is_empty() {
            return fail("Quit application before activating update; installed bundle retained");
        }
        if !disk.is_null() {
            let old = metadata(&target)?;
            if old["build"] != a["build"] {
                upgrade(&old, a)?;
            }
        }
        if !record.is_null() && !identity.is_null() && record["selection"]["signer"] != identity {
            return fail("Signing identity migration requires explicit review");
        }
    }
    Ok(json!({"app":a,"selection":selection,"installed":disk,"current":current,"running":live}))
}
fn install_managed(m: &V, plan: &V) -> Result<String> {
    let a = &plan["app"];
    if plan["current"] == true {
        save(
            &record_path(&p(m, "stateDirectory"), s(a, "bundle")),
            &json!({"selection":plan["selection"],"installed":plan["installed"]}),
        )?;
        return Ok("unchanged".into());
    }
    let target = p(m, "appsDirectory").join(s(a, "bundle"));
    fs::create_dir_all(target.parent().ok_or("Missing parent")?)?;
    let temp = transaction().tempdir_in(
        target
            .parent()
            .and_then(Path::parent)
            .ok_or("Missing app parent")?,
    )?;
    let dir = temp.path().to_owned();
    let staged = dir.join(s(a, "bundle"));
    let mut temp = Some(temp);
    let result = (|| -> Result<()> {
        copy(m, &p(a, "source"), &staged)?;
        let identity = &plan["selection"]["signer"];
        if !identity.is_null() {
            sign(&staged, identity)?;
        }
        let installed = signature(&staged, true)?;
        if installed["identifier"] != a["bundleId"] {
            return fail("Installed signing identifier differs from bundle identifier");
        }
        if identity.is_null() && installed != plan["selection"]["sourceIdentity"] {
            return fail("Copying changed vendor signing identity");
        }
        if s(&plan["installed"], "kind") == "certificate" {
            command(&[
                "/usr/bin/codesign",
                "--verify",
                "-R",
                &format!("={}", s(&plan["installed"], "requirement")),
                staged.to_str().ok_or("Invalid path")?,
            ])?;
        }
        if managed_plan(m, a)? != *plan {
            return fail("Application state changed during staging; installed bundle retained");
        }
        let evidence = json!({"canonical":target,"selection":plan["selection"],"previous":plan["installed"],"installed":installed});
        journal(&dir, "install-intent", &evidence)?;
        if let Some(t) = temp.take() {
            let _retained_path = t.keep();
        }
        swap(&staged, &target)?;
        if signature(&target, true)? != installed {
            return fail("Installed bundle changed during commit");
        }
        if staged.exists() {
            unregister(m, a, &staged, &[])?;
        }
        register(&target)?;
        journal(&dir, "installed", &evidence)?;
        save(
            &record_path(&p(m, "stateDirectory"), s(a, "bundle")),
            &json!({"selection":plan["selection"],"installed":installed}),
        )?;
        Ok(())
    })();
    if let Err(e) = result {
        if temp.is_none() {
            return fail(&format!("{e}; recovery retained in {}", dir.display()));
        }
        return Err(e);
    }
    Ok(format!("installed; recovery retained in {}", dir.display()))
}
fn retired(m: &V, selected: &[V]) -> Result<Vec<V>> {
    let mut names = BTreeSet::new();
    for a in selected.iter().chain(array(&m["apps"])?.iter()) {
        names.insert(s(a, "bundle").to_owned());
    }
    let state = p(m, "stateDirectory");
    if !state.exists() {
        return Ok(vec![]);
    }
    let mut out = vec![];
    for entry in fs::read_dir(&state)? {
        let path = entry?.path();
        if path.extension().and_then(|e| e.to_str()) != Some("json") {
            continue;
        }
        let record = read_private(&path)?;
        let selection = record.get("selection").cloned().unwrap_or(json!({}));
        if !selection.is_object() {
            return fail("Malformed application retirement record");
        }
        let Some(bundle) = selection["bundle"].as_str() else {
            continue;
        };
        if names.contains(bundle) {
            continue;
        }
        if !bundle_name(bundle) {
            return fail("Invalid owned application retirement record");
        }
        let a = json!({"bundle":bundle,"bundleId":selection["bundleId"]});
        if path != record_path(&state, bundle) {
            return fail("Application retirement record has unexpected filename");
        }
        let target = p(m, "appsDirectory").join(bundle);
        if target.is_symlink()
            || !target.is_dir()
            || signature(&target, true)? != record["installed"]
        {
            return fail("Deselected application changed; review before retirement");
        }
        if !array(&running(m, &a)?)?.is_empty() {
            return fail("Quit application before retiring managed copy");
        }
        out.push(a);
    }
    Ok(out)
}
fn retire(m: &V, a: &V) -> Result<()> {
    let target = p(m, "appsDirectory").join(s(a, "bundle"));
    let dir = transaction()
        .tempdir_in(
            target
                .parent()
                .and_then(Path::parent)
                .ok_or("Missing parent")?,
        )?
        .keep();
    let record = read_private(&record_path(&p(m, "stateDirectory"), s(a, "bundle")))?;
    if record.is_null()
        || !array(&running(m, a)?)?.is_empty()
        || signature(&target, true)? != record["installed"]
    {
        return fail("Deselected application changed before retirement");
    }
    let evidence = json!({"canonical":target,"record":record});
    journal(&dir, "retire-intent", &evidence)?;
    let backup = dir.join(s(a, "bundle"));
    rename(&target, &backup, false)?;
    unregister(m, a, &target, &[])?;
    unregister(m, a, &backup, &[])?;
    journal(&dir, "retired", &evidence)?;
    fs::remove_file(record_path(&p(m, "stateDirectory"), s(a, "bundle")))?;
    Ok(())
}
fn execute(m: &V, mode: &str) -> Result<V> {
    let mut results = vec![];
    if m["manageAll"] == true {
        let selected = selected(m)?;
        let plans = selected
            .iter()
            .map(|a| managed_plan(m, a))
            .collect::<Result<Vec<_>>>()?;
        let retired = retired(m, &selected)?;
        if !retired.is_empty() && !matches!(mode, "install" | "preflight") {
            return fail("Deselected managed applications remain; activation required");
        }
        if mode == "install" {
            for a in retired {
                retire(m, &a)?;
            }
        }
        for plan in plans {
            let result = match mode {
                "install" => install_managed(m, &plan)?,
                "preflight" => "safe".into(),
                _ => {
                    if plan["current"] != true {
                        return fail("Installed identity differs from Nix; activation required");
                    }
                    if array(&plan["running"])?.is_empty() {
                        "not-running"
                    } else {
                        "ready"
                    }
                    .into()
                }
            };
            results.push(json!({"bundle":plan["app"]["bundle"],"status":result,"identityStability":if plan["selection"]["signer"].is_null(){"preserved-certificate"}else{"local-certificate"}}));
        }
    }
    for a in array(&m["apps"])? {
        let target = p(m, "appsDirectory").join(s(a, "bundle"));
        let mut report = json!({"bundle":a["bundle"]});
        let status = match mode {
            "preflight" => {
                preflight(m, a)?;
                "safe".into()
            }
            "install" => protected_install(m, a)?,
            _ => {
                let source = inspect(&p(a, "source"), a)?;
                if !previous_identities(m, a, &p(m, "appsDirectory"), &source)?.is_empty() {
                    return fail(
                        "Previous canonical application remains; guarded migration required",
                    );
                }
                let (disk, live) = inspect_live(m, a, &target)?;
                if disk != source {
                    return fail("Installed identity differs from Nix; activation required");
                }
                let status = if array(&live)?.is_empty() {
                    "not-running"
                } else {
                    "ready"
                };
                report["running"] = live;
                if mode == "refresh" {
                    register(&target)?;
                }
                status.into()
            }
        };
        report["status"] = json!(status);
        results.push(report);
    }
    Ok(json!({"status":"ok","apps":results,"authorization":"unknown"}))
}
fn blocked(e: impl std::fmt::Display) -> V {
    json!({"status":"blocked","error":e.to_string(),"authorization":"unknown"})
}
fn perform(m: &V, mode: &str) -> Result<V> {
    let state = p(m, "stateDirectory");
    check_state(&state)?;
    let mutate = matches!(mode, "install" | "refresh" | "observe");
    let _lock = if mutate { Some(lock(&state)?) } else { None };
    let report = match execute(m, mode) {
        Ok(v) => v,
        Err(e) if matches!(mode, "refresh" | "observe") => blocked(e),
        Err(e) => return Err(e),
    };
    if matches!(mode, "refresh" | "observe") {
        let target = state.join("status.json");
        let value = format!("{}\n", serde_json::to_string(&report)?);
        let old = if target.is_file() && !target.is_symlink() {
            fs::read_to_string(&target)?
        } else {
            String::new()
        };
        if old != value {
            atomic(&target, value.as_bytes(), false)?;
            if report["status"] == "blocked" {
                let _diagnostic_result = command(&[
                    "/usr/bin/osascript",
                    "-e",
                    "display notification \"Run hm-macos-applications --check for details.\" with title \"Managed application needs attention\"",
                ]);
            }
        }
    }
    Ok(report)
}
fn owned_recovery(path: &Path, canonical: &Path, a: &V) -> Result<bool> {
    let parent = path.parent().ok_or("Missing parent")?;
    let name = parent.file_name().and_then(|s| s.to_str()).unwrap_or("");
    let mut names = previous(a, Path::new("/"))?
        .iter()
        .filter_map(|p| p.file_name().map(|s| s.to_owned()))
        .collect::<Vec<_>>();
    names.push(s(a, "bundle").into());
    Ok(parent.parent() == canonical.parent().and_then(Path::parent)
        && name.starts_with(".hm-app-update-")
        && name.ends_with(".noindex")
        && path
            .file_name()
            .is_some_and(|s| names.contains(&s.to_owned())))
}
fn reconcile_system(m: &V, a: &V, prefix: &[String]) -> Result<()> {
    let canonical = p(m, "appsDirectory").join(s(a, "bundle"));
    let previous: BTreeSet<_> = previous(a, &p(m, "appsDirectory"))?.into_iter().collect();
    let mut candidates = registered(m, a, &[])?;
    candidates.extend(registered(m, a, prefix)?);
    candidates.extend(previous.iter().cloned());
    candidates.remove(&canonical);
    // Validate the entire plan before either registry is mutated.
    for candidate in &candidates {
        let recovery = owned_recovery(candidate, &canonical, a)?;
        if !(previous.contains(candidate)
            || re(r"^/nix/store/[^/]+/Applications/[^/]+\.app$")
                .is_match(&candidate.to_string_lossy())
            || recovery)
        {
            return fail("Competing application registration requires inspection");
        }
        if candidate.is_symlink() || (recovery && candidate.parent().is_some_and(Path::is_symlink))
        {
            return fail("Refusing registration cleanup through symlink");
        }
        if candidate.exists() {
            inspect(candidate, a)?;
        }
    }
    for candidate in candidates {
        unregister(m, a, &candidate, &[])?;
        unregister(m, a, &candidate, prefix)?;
    }
    register(&canonical)?;
    let mut args = prefix.to_vec();
    args.extend([
        LS.to_owned(),
        "-f".into(),
        canonical.to_string_lossy().into_owned(),
    ]);
    run_owned(&args)?;
    let expected = BTreeSet::from([canonical]);
    if registered(m, a, &[])? != expected || registered(m, a, prefix)? != expected {
        return fail("Canonical registration could not be established in both contexts");
    }
    Ok(())
}
fn refresh_system(m: &V, manifest: &Path, changed: bool) -> Result<V> {
    if !rustix::process::geteuid().is_root() {
        return fail("System registration refresh requires root; use Darwin activation hook");
    }
    let state = Path::new("/var/run/macos-application-registry");
    let _lock = lock(state)?;
    // id resolves the configured login through the system account database.
    let uid = command(&["/usr/bin/id", "-u", s(m, "username")])?
        .trim()
        .parse::<u32>()?;
    let prefix = vec![
        "/bin/launchctl".into(),
        "asuser".into(),
        uid.to_string(),
        "/usr/bin/sudo".into(),
        format!("--user={}", s(m, "username")),
        "--".into(),
    ];
    let mut args = prefix.clone();
    args.extend([
        std::env::current_exe()?.to_string_lossy().into_owned(),
        "--manifest".into(),
        manifest.to_string_lossy().into_owned(),
        "--mode".into(),
        "check".into(),
    ]);
    let report: V = serde_json::from_str(&run_owned(&args)?)?;
    if report["status"] != "ok" {
        return fail("User-context identity inspection failed");
    }
    let mut verified = vec![];
    for a in array(&m["apps"])? {
        let path = p(m, "appsDirectory").join(s(a, "bundle"));
        let identity = inspect(&path, a)?;
        if path.is_symlink() || identity != inspect(&p(a, "source"), a)? {
            return fail(
                "Refusing system registration of bundle differing from selected verified source",
            );
        }
        verified.push(json!({"path":path,"source":a["source"],"identity":identity,"previous":previous(a,path.parent().ok_or("Missing parent")?)?}));
    }
    let fingerprint = format!(
        "{}\n",
        serde_json::to_string(&json!({"verified":verified,"runtime":report}))?
    );
    let ledger = state.join("registered.json");
    if changed && ledger.is_file() && fs::read_to_string(&ledger)? == fingerprint {
        return Ok(json!({"status":"ok","registration":"current","authorization":"unknown"}));
    }
    let mut results = vec![];
    for a in array(&m["apps"])? {
        reconcile_system(m, a, &prefix)?;
        results.push(json!({"bundle":a["bundle"],"status":"registered-system-and-user"}));
    }
    atomic(&ledger, fingerprint.as_bytes(), false)?;
    Ok(json!({"status":"ok","apps":results,"authorization":"unknown"}))
}
fn canonical_path(s: &str) -> bool {
    s.starts_with('/')
        && (s == "/"
            || s.split('/')
                .skip(1)
                .all(|p| !p.is_empty() && p != "." && p != ".."))
}
fn validate(m: &V) -> Result<()> {
    for key in [
        "appsDirectory",
        "stateDirectory",
        "queryScript",
        "rsync",
        "registryHelper",
        "selectedApplications",
    ] {
        if !canonical_path(s(m, key)) {
            return fail(&format!("Invalid manifest path: {key}"));
        }
    }
    let mut names = BTreeSet::new();
    let mut ids = BTreeSet::new();
    for a in array(&m["apps"])? {
        if !bundle_name(s(a, "bundle"))
            || s(a, "bundleId").is_empty()
            || s(a, "teamId").is_empty()
            || !canonical_path(s(a, "source"))
        {
            return fail("Invalid protected application manifest");
        }
        if !ids.insert(s(a, "bundleId")) {
            return fail("Duplicate protected application identifier");
        }
        let mut paths = previous(a, Path::new("/"))?;
        paths.push(Path::new("/").join(s(a, "bundle")));
        for path in paths {
            if !names.insert(path.to_string_lossy().case_fold().collect::<String>()) {
                return fail("Ambiguous protected application names");
            }
        }
    }
    Ok(())
}
fn main() -> std::process::ExitCode {
    let args = Args::parse();
    if args.if_changed && args.mode != "refresh-system" {
        use clap::CommandFactory;
        Args::command()
            .error(
                clap::error::ErrorKind::ArgumentConflict,
                "--if-changed requires --mode refresh-system",
            )
            .exit();
    }
    let result = (|| -> Result<V> {
        let m: V = serde_json::from_slice(&fs::read(&args.manifest)?)?;
        validate(&m)?;
        match args.mode.as_str() {
            "inventory" => inventory(&m),
            "enroll-identity" => enroll(&m),
            "refresh-system" => refresh_system(&m, &args.manifest, args.if_changed),
            mode => perform(&m, mode),
        }
    })();
    let report = result.unwrap_or_else(blocked);
    println!("{report}");
    if report["status"] == "ok" {
        std::process::ExitCode::SUCCESS
    } else {
        std::process::ExitCode::FAILURE
    }
}
