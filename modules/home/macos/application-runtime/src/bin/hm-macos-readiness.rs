//! Identity inspection and explicit operator-reported capability receipts.
use clap::Parser;
use fs2::FileExt;
use macos_application_tools::{Result, fail};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    collections::{BTreeMap, HashSet},
    fs::{self, DirBuilder, OpenOptions},
    io::Write,
    os::unix::fs::{DirBuilderExt, MetadataExt, OpenOptionsExt},
    path::{Path, PathBuf},
    time::Duration,
};
use unicode_casefold::UnicodeCaseFold;
const SERVICES: &[&str] = &[
    "accessibility",
    "local-network",
    "camera",
    "microphone",
    "screen-recording",
    "input-monitoring",
    "full-disk-access",
    "apple-events",
    "notifications",
    "browser-integration",
    "protected-files",
    "background-items",
];
#[derive(Parser)]
struct Args {
    #[arg(long)]
    manifest: PathBuf,
    #[arg(long,conflicts_with_all=["guide","verify"])]
    check: bool,
    #[arg(long, num_args = 2, conflicts_with = "verify")]
    guide: Vec<String>,
    #[arg(long, num_args = 2)]
    verify: Vec<String>,
    #[arg(long)]
    json: bool,
    #[arg(long,value_parser=["app","settings"])]
    open: Option<String>,
    #[arg(long,value_parser=["passed","failed"])]
    result: Option<String>,
    #[arg(long,value_parser=["gui-app"])]
    origin: Option<String>,
    #[arg(long)]
    evidence: Option<String>,
}
struct Feature {
    name: String,
    service: String,
    reason: String,
    source: String,
    instruction: String,
    minimum: u64,
}
struct App {
    name: String,
    bundle: String,
    id: String,
    team: Option<String>,
    features: Vec<Feature>,
}
struct Manifest {
    apps: Vec<App>,
    directory: PathBuf,
    state: PathBuf,
}
struct Identity {
    id: String,
    version: String,
    team: Option<String>,
    kind: String,
    fingerprint: String,
}
fn object(v: &Value) -> Result<&serde_json::Map<String, Value>> {
    v.as_object().ok_or_else(|| "Expected an object".into())
}
fn text(v: &Value) -> Result<String> {
    v.as_str()
        .filter(|s| !s.trim().is_empty())
        .map(str::to_owned)
        .ok_or_else(|| "Expected nonempty text".into())
}
fn key(s: &str) -> Result<String> {
    if !regex::Regex::new(r"^[a-zA-Z0-9][a-zA-Z0-9_.-]*$")?.is_match(s) {
        return fail("Invalid application or feature key");
    }
    Ok(s.to_owned())
}
fn manifest(path: &Path) -> Result<Manifest> {
    let data: Value = serde_json::from_slice(&fs::read(path)?)?;
    object(&data)?;
    if data["schemaVersion"].as_u64() != Some(1) {
        return fail("Unsupported manifest version");
    }
    let mut apps = vec![];
    let mut bundles = HashSet::new();
    let mut ids = HashSet::new();
    for (name, item) in object(&data["apps"])? {
        object(item)?;
        let bundle = text(&item["bundle"])?;
        let id = text(&item["bundleId"])?;
        if Path::new(&bundle).file_name().and_then(|s| s.to_str()) != Some(&bundle)
            || !bundle.ends_with(".app")
        {
            return fail("Expected a top-level .app bundle");
        }
        if !bundles.insert(bundle.case_fold().collect::<String>()) || !ids.insert(id.clone()) {
            return fail("Duplicate bundle path or identifier");
        }
        let team = if item["teamId"].is_null() {
            None
        } else {
            Some(text(&item["teamId"])?)
        };
        let mut features = vec![];
        for (feature_name, feature) in object(&item["features"])? {
            object(feature)?;
            let service = text(&feature["service"])?;
            let source = text(&feature["source"])?;
            if !SERVICES.contains(&service.as_str()) || !source.starts_with("https://") {
                return fail("Unsupported service or evidence source");
            }
            let minimum = feature["minimumOS"]
                .as_u64()
                .filter(|v| *v >= 13)
                .ok_or("Expected a supported macOS major version")?;
            features.push(Feature {
                name: key(feature_name)?,
                minimum: if service == "local-network" {
                    minimum.max(15)
                } else {
                    minimum
                },
                service,
                source,
                reason: text(&feature["reason"])?,
                instruction: text(&feature["instruction"])?,
            });
        }
        apps.push(App {
            name: key(name)?,
            bundle,
            id,
            team,
            features,
        });
    }
    let directory = PathBuf::from(text(&data["appsDirectory"])?);
    let state = PathBuf::from(text(&data["stateDirectory"])?);
    if !directory.is_absolute() || !state.is_absolute() {
        return fail("Manifest directories must be absolute");
    }
    Ok(Manifest {
        apps,
        directory,
        state,
    })
}
// Match json.dumps(sort_keys=True), including spaces and ensure_ascii, so old
// receipts keep their identities across the language migration.
fn canonical(value: &Value) -> Result<String> {
    Ok(match value {
        Value::String(value) => {
            let encoded = serde_json::to_string(value)?;
            let mut ascii = String::new();
            for c in encoded.chars() {
                if c.is_ascii() {
                    ascii.push(c);
                } else {
                    let mut units = [0; 2];
                    for unit in c.encode_utf16(&mut units) {
                        ascii.push_str(&format!("\\u{unit:04x}"));
                    }
                }
            }
            ascii
        }
        Value::Array(values) => format!(
            "[{}]",
            values
                .iter()
                .map(canonical)
                .collect::<Result<Vec<_>>>()?
                .join(", ")
        ),
        Value::Object(values) => {
            let sorted: BTreeMap<_, _> = values.iter().collect();
            format!(
                "{{{}}}",
                sorted
                    .iter()
                    .map(|(k, v)| Ok(format!("{}: {}", canonical(&json!(k))?, canonical(v)?)))
                    .collect::<Result<Vec<_>>>()?
                    .join(", ")
            )
        }
        _ => serde_json::to_string(value)?,
    })
}
fn digest(value: &Value) -> Result<String> {
    Ok(format!(
        "{:x}",
        Sha256::digest(canonical(value)?.as_bytes())
    ))
}
async fn native(program: &str, args: &[&str]) -> Result<String> {
    let result = nix_conf_process::run(
        tokio::process::Command::new(program).args(args),
        None,
        Duration::from_secs(30),
    )
    .await?;
    if !result.status.success() {
        let error = String::from_utf8_lossy(&result.stderr);
        let error = error.trim();
        return fail(&if error.is_empty() {
            "Native inspection failed".to_owned()
        } else {
            error.chars().take(1000).collect()
        });
    }
    Ok(String::from_utf8(result.stdout)? + &String::from_utf8(result.stderr)?)
}
async fn system() -> Result<(String, String)> {
    if !cfg!(target_os = "macos") {
        return fail("Native readiness inspection requires macOS");
    }
    Ok((
        native("/usr/bin/sw_vers", &["-productVersion"])
            .await?
            .trim()
            .to_owned(),
        native("/usr/bin/sw_vers", &["-buildVersion"])
            .await?
            .trim()
            .to_owned(),
    ))
}
async fn inspect(path: &Path) -> Result<Identity> {
    if path.is_symlink() || !path.is_dir() {
        return fail("Canonical app must be an existing copied directory");
    }
    let metadata = plist::Value::from_file(path.join("Contents/Info.plist"))?;
    let metadata = metadata.as_dictionary().ok_or("Expected an object")?;
    let id = metadata
        .get("CFBundleIdentifier")
        .and_then(plist::Value::as_string)
        .filter(|s| !s.trim().is_empty())
        .ok_or("Expected nonempty text")?
        .to_owned();
    let version = metadata
        .get("CFBundleShortVersionString")
        .filter(|v| v.as_string().is_some_and(|s| !s.is_empty()))
        .or_else(|| metadata.get("CFBundleVersion"))
        .and_then(plist::Value::as_string)
        .filter(|s| !s.trim().is_empty())
        .ok_or("Expected nonempty text")?
        .to_owned();
    let p = path.to_str().ok_or("Invalid native path")?;
    native(
        "/usr/bin/codesign",
        &["--verify", "--deep", "--strict", "--all-architectures", p],
    )
    .await?;
    let details = native("/usr/bin/codesign", &["--display", "--verbose=4", "-r-", p]).await?;
    let fields = details
        .lines()
        .filter_map(|l| l.split_once('='))
        .collect::<BTreeMap<_, _>>();
    if fields.get("Identifier").copied() != Some(&id) {
        return fail("Signed executable identifier does not match Info.plist");
    }
    let requirement = fields
        .get("designated ")
        .or_else(|| fields.get("# designated "))
        .copied()
        .unwrap_or("")
        .strip_prefix("> ")
        .unwrap_or_else(|| {
            fields
                .get("designated ")
                .or_else(|| fields.get("# designated "))
                .copied()
                .unwrap_or("")
        })
        .trim();
    if requirement.is_empty() {
        return fail("Expected nonempty text");
    }
    let cdhash = fields
        .get("CDHash")
        .filter(|v| !v.trim().is_empty())
        .ok_or("Expected nonempty text")?;
    let team = fields
        .get("TeamIdentifier")
        .filter(|v| **v != "not set")
        .map(|v| v.to_string());
    let kind = if fields.get("Signature").copied() == Some("adhoc") {
        "ad-hoc"
    } else {
        "certificate"
    }
    .to_owned();
    let fingerprint = digest(&json!([
        path.canonicalize()?,
        id,
        version,
        team,
        requirement,
        cdhash
    ]))?;
    Ok(Identity {
        id,
        version,
        team,
        kind,
        fingerprint,
    })
}
async fn inspect_apps(
    manifest: &Manifest,
) -> (BTreeMap<String, Identity>, BTreeMap<String, String>) {
    let mut identities = BTreeMap::new();
    let mut errors = BTreeMap::new();
    let mut observed = BTreeMap::<String, String>::new();
    for app in &manifest.apps {
        let identity = match inspect(&manifest.directory.join(&app.bundle)).await {
            Ok(i) => i,
            Err(e) => {
                errors.insert(app.name.clone(), e.to_string());
                continue;
            }
        };
        if let Some(previous) = observed.insert(identity.id.clone(), app.name.clone()) {
            errors.insert(previous, "Duplicate observed bundle identifier".to_owned());
            errors.insert(
                app.name.clone(),
                "Duplicate observed bundle identifier".to_owned(),
            );
        }
        if identity.id != app.id || (app.team.is_some() && identity.team != app.team) {
            errors.insert(
                app.name.clone(),
                "Installed bundle or vendor team does not match the manifest".to_owned(),
            );
        }
        identities.insert(app.name.clone(), identity);
    }
    (identities, errors)
}
fn observation(
    app: &App,
    feature: &Feature,
    identity: &Identity,
    system: &(String, String),
) -> Result<String> {
    digest(&json!([
        app.name,
        feature.name,
        feature.service,
        feature.reason,
        feature.instruction,
        identity.fingerprint,
        system
    ]))
}
fn receipt_path(manifest: &Manifest, app: &App, feature: &Feature) -> Result<PathBuf> {
    Ok(manifest.state.join(format!(
        "{}.json",
        digest(&json!([app.name, feature.name]))?
    )))
}
fn read_receipt(path: &Path, expected: &str) -> Value {
    if !path.exists() {
        return Value::Null;
    }
    if path.is_symlink() || path.parent().is_some_and(Path::is_symlink) {
        return json!({"stale":true,"error":"Evidence symlink rejected"});
    }
    let read = (|| -> Result<Value> {
        let mut data: Value = serde_json::from_slice(&fs::read(path)?)?;
        object(&data)?;
        let valid = data["schemaVersion"].as_u64() == Some(1)
            && matches!(data["result"].as_str(), Some("passed" | "failed"))
            && data["origin"] == "gui-app"
            && data["provenance"] == "operator-reported-feature-test"
            && [
                "evidence",
                "verifiedAt",
                "appVersion",
                "identityFingerprint",
                "osBuild",
            ]
            .iter()
            .all(|k| data[k].is_string());
        if !valid {
            return fail("Malformed receipt");
        }
        data["stale"] = json!(data["observationKey"].as_str() != Some(expected));
        Ok(data)
    })();
    read.unwrap_or_else(
        |_| json!({"stale":true,"error":"Unreadable or malformed historical evidence"}),
    )
}
fn write_receipt(path: &Path, value: &Value) -> Result<()> {
    let directory = path.parent().ok_or("Receipt has no parent")?;
    DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(directory)?;
    let metadata = fs::metadata(directory)?;
    if directory.is_symlink() || metadata.uid() != rustix::process::getuid().as_raw() {
        return fail("Evidence directory must be owned by the current user and not a symlink");
    }
    if metadata.mode() & 0o077 != 0 {
        return fail("Evidence directory must be private (mode 0700)");
    }
    let lock = OpenOptions::new()
        .create(true)
        .read(true)
        .write(true)
        .truncate(false)
        .mode(0o600)
        .custom_flags(rustix::fs::OFlags::NOFOLLOW.bits() as i32)
        .open(directory.join(".lock"))?;
    lock.lock_exclusive()?;
    let mut file = tempfile::Builder::new()
        .prefix(".receipt-")
        .tempfile_in(directory)?;
    serde_json::to_writer(&mut file, value)?;
    writeln!(file)?;
    file.flush()?;
    file.as_file().sync_all()?;
    file.persist(path).map_err(|e| e.error)?;
    Ok(())
}
async fn report(manifest: &Manifest) -> Result<Value> {
    let system = system().await?;
    let major = system
        .0
        .split('.')
        .next()
        .ok_or("Invalid OS version")?
        .parse::<u64>()?;
    let (identities, errors) = inspect_apps(manifest).await;
    let mut apps = vec![];
    for app in &manifest.apps {
        let identity = identities.get(&app.name);
        let mut features = vec![];
        for feature in &app.features {
            let status = if errors.contains_key(&app.name) {
                "blocked-identity"
            } else if major < feature.minimum {
                "unsupported"
            } else {
                "unknown"
            };
            let historical = if let Some(identity) = identity {
                read_receipt(
                    &receipt_path(manifest, app, feature)?,
                    &observation(app, feature, identity, &system)?,
                )
            } else {
                Value::Null
            };
            features.push(json!({"key":feature.name,"service":feature.service,"status":status,"observed":"unknown","reason":feature.reason,"nextAction":feature.instruction,"source":feature.source,"lastVerification":historical}));
        }
        apps.push(json!({"key":app.name,"bundle":app.bundle,"identityStatus":if errors.contains_key(&app.name){"blocked-identity"}else{"ready"},"error":errors.get(&app.name),"bundleId":identity.map(|i|&i.id),"version":identity.map(|i|&i.version),"signingKind":identity.map(|i|&i.kind),"features":features}));
    }
    Ok(json!({"schemaVersion":1,"osVersion":system.0,"osBuild":system.1,"apps":apps}))
}
async fn execute(args: Args) -> Result<i32> {
    if args.open.is_some() && args.guide.is_empty() {
        return fail("--open requires --guide");
    }
    if (args.result.is_some() || args.origin.is_some() || args.evidence.is_some())
        && args.verify.is_empty()
    {
        return fail("Evidence arguments require --verify");
    }
    let manifest = manifest(&args.manifest)?;
    if !args.guide.is_empty() || !args.verify.is_empty() {
        let names = if args.guide.is_empty() {
            &args.verify
        } else {
            &args.guide
        };
        let app = manifest
            .apps
            .iter()
            .find(|a| a.name == names[0])
            .ok_or("Application/feature is not selected in the manifest")?;
        let feature = app
            .features
            .iter()
            .find(|f| f.name == names[1])
            .ok_or("Application/feature is not selected in the manifest")?;
        let system = system().await?;
        let (identities, errors) = inspect_apps(&manifest).await;
        if let Some(error) = errors.get(&app.name) {
            return fail(error);
        }
        if system
            .0
            .split('.')
            .next()
            .ok_or("Invalid OS version")?
            .parse::<u64>()?
            < feature.minimum
        {
            return fail("Capability unsupported on this OS");
        }
        let output = if !args.guide.is_empty() {
            if let Some(open) = args.open {
                if open == "settings" {
                    native("/usr/bin/open", &["-a", "System Settings"]).await?;
                } else {
                    native(
                        "/usr/bin/open",
                        &[manifest
                            .directory
                            .join(&app.bundle)
                            .to_str()
                            .ok_or("Invalid app path")?],
                    )
                    .await?;
                }
            }
            json!({"app":app.name,"feature":feature.name,"instruction":feature.instruction,"source":feature.source})
        } else {
            if args.result.is_none()
                || args.origin.as_deref() != Some("gui-app")
                || args.evidence.as_ref().is_none_or(|e| e.trim().is_empty())
            {
                return fail(
                    "--verify requires --result, --origin gui-app and --evidence describing a performed feature test",
                );
            }
            let identity = identities.get(&app.name).ok_or("Missing app identity")?;
            let receipt = json!({"schemaVersion":1,"result":args.result,"origin":args.origin,"evidence":args.evidence,"verifiedAt":time::OffsetDateTime::now_utc().format(&time::format_description::well_known::Rfc3339)?,"observationKey":observation(app,feature,identity,&system)?,"provenance":"operator-reported-feature-test","app":app.name,"feature":feature.name,"service":feature.service,"bundleId":identity.id,"appVersion":identity.version,"identityFingerprint":identity.fingerprint,"osVersion":system.0,"osBuild":system.1});
            write_receipt(&receipt_path(&manifest, app, feature)?, &receipt)?;
            let mut output = receipt;
            output["recorded"] = json!(true);
            output["currentAuthorization"] = json!("unknown");
            output
        };
        println!(
            "{}",
            if args.json {
                serde_json::to_string(&output)?
            } else {
                serde_json::to_string_pretty(&output)?
            }
        );
        return Ok(0);
    }
    let snapshot = report(&manifest).await?;
    let apps = snapshot["apps"].as_array().ok_or("Invalid snapshot")?;
    if args.json {
        println!("{}", serde_json::to_string(&snapshot)?);
    } else {
        for app in apps {
            print!(
                "{}: identity {}",
                app["key"].as_str().unwrap_or(""),
                app["identityStatus"].as_str().unwrap_or("")
            );
            if let Some(error) = app["error"].as_str() {
                print!(" ({error})");
            }
            println!();
            if let Some(features) = app["features"].as_array() {
                for f in features {
                    println!(
                        "  {}: {} — {}",
                        f["key"].as_str().unwrap_or(""),
                        f["status"].as_str().unwrap_or(""),
                        f["nextAction"].as_str().unwrap_or("")
                    );
                }
            }
        }
    }
    Ok(
        if apps
            .iter()
            .any(|a| a["identityStatus"] == "blocked-identity")
        {
            1
        } else if apps
            .iter()
            .any(|a| a["features"].as_array().is_some_and(|f| !f.is_empty()))
        {
            2
        } else {
            0
        },
    )
}
#[tokio::main(flavor = "current_thread")]
async fn main() {
    let code = match execute(Args::parse()).await {
        Ok(code) => code,
        Err(error) => {
            eprintln!("hm-macos-readiness: {error}");
            1
        }
    };
    std::process::exit(code);
}
