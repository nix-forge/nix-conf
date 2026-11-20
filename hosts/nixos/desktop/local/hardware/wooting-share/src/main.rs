//! Explicit publication of generated profiles; Wootility owns device writes.
use fs2::FileExt;
use reqwest::{Client, Method};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::error::Error;
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Write};
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

mod validation;

type Result<T> = std::result::Result<T, Box<dyn Error>>;
const ENDPOINT: &str = "https://api.wooting.io/public/wootility/profiles";
const ADAPTER: &str = "wootility-5.4.2-schema15-v1";
const MAX_PROFILE: usize = 1_048_576;
const MAX_RESPONSE: usize = 2 * MAX_PROFILE;
const HELP: &str =
    "wooting-profile-share <validate|publish|verify|compare-import> --profile FILE [OPTIONS]

validate                  Validate locally; no network or state writes
publish                   Upload once, verify read-back, or reuse a matching code
verify                    Verify and record a cached or supplied code; never upload
compare-import            Compare a Wootility re-shared profile; no release-state writes

--state-dir DIR           Private release directory (default: user state directory)
--code CODE               Existing code for verify, or re-shared code for compare-import
--imported FILE           Native re-export for offline compare-import (instead of --code)
--republish               Intentionally publish again, archiving the previous record
--json                    Emit a machine-readable result on stdout

publish uploads the complete profile to Wooting's service. Builds, login and OS
activation never invoke it. An uncertain POST is never automatically repeated.
No command writes to a keyboard. Supports the reviewed schema 15 ANSI 80HE
DIGITAL TYPING SUBSET only: two layers, no advanced keys, RT, gamepad mappings
or RGB effects. Unsupported settings are rejected, never silently discarded.
compare-import checks supplied content; it does not execute or authenticate an
app conversion. Use the Wootility import modal and re-share the imported profile.";

struct Args {
    action: String,
    profile: PathBuf,
    state_dir: PathBuf,
    code: Option<String>,
    imported: Option<PathBuf>,
    republish: bool,
    json: bool,
}

fn default_state_dir() -> Result<PathBuf> {
    if let Some(path) = std::env::var_os("XDG_STATE_HOME") {
        let path = PathBuf::from(path);
        if !path.is_absolute() {
            return Err("XDG_STATE_HOME must be absolute".into());
        }
        return Ok(path.join("wooting-profile-share"));
    }
    let home = PathBuf::from(std::env::var_os("HOME").ok_or("HOME is not set")?);
    if !home.is_absolute() {
        return Err("HOME must be absolute".into());
    }
    Ok(home.join(if cfg!(target_os = "macos") {
        "Library/Application Support/wooting-profile-share"
    } else {
        ".local/state/wooting-profile-share"
    }))
}

fn parse_args() -> Result<Option<Args>> {
    let mut args = std::env::args_os().skip(1);
    let Some(action) = args.next() else {
        return Err(HELP.into());
    };
    if action == "--help" || action == "-h" {
        println!("{HELP}");
        return Ok(None);
    }
    let action = action.into_string().map_err(|_| "invalid command")?;
    if !["validate", "publish", "verify", "compare-import"].contains(&action.as_str()) {
        return Err(format!("unknown command {action:?}\n{HELP}").into());
    }
    let mut profile = None;
    let mut state_dir = None;
    let mut code = None;
    let mut imported = None;
    let mut republish = false;
    let mut json = false;
    while let Some(arg) = args.next() {
        match arg.to_str() {
            Some("--profile") if profile.is_none() => {
                profile = Some(PathBuf::from(args.next().ok_or("missing --profile value")?));
            }
            Some("--state-dir") if state_dir.is_none() => {
                state_dir = Some(PathBuf::from(
                    args.next().ok_or("missing --state-dir value")?,
                ));
            }
            Some("--code") if code.is_none() => {
                code = Some(
                    args.next()
                        .ok_or("missing --code value")?
                        .into_string()
                        .map_err(|_| "invalid code")?,
                );
            }
            Some("--imported") if imported.is_none() => {
                imported = Some(PathBuf::from(
                    args.next().ok_or("missing --imported value")?,
                ));
            }
            Some("--republish") if !republish => republish = true,
            Some("--json") if !json => json = true,
            Some("--help" | "-h") => {
                println!("{HELP}");
                return Ok(None);
            }
            _ => return Err(format!("unknown or duplicate option {arg:?}").into()),
        }
    }
    if code.is_some() && !["verify", "compare-import"].contains(&action.as_str())
        || republish && action != "publish"
    {
        return Err(
            "--code requires verify or compare-import; --republish requires publish".into(),
        );
    }
    if imported.is_some() && action != "compare-import"
        || action == "compare-import" && (imported.is_some() == code.is_some())
    {
        return Err("compare-import requires exactly one of --imported FILE or --code CODE".into());
    }
    if let Some(code) = &code {
        valid_code(code)?;
    }
    let state_dir = match state_dir {
        Some(path) => path,
        None if action == "validate" || action == "compare-import" => PathBuf::new(),
        None => default_state_dir()?,
    };
    Ok(Some(Args {
        action,
        profile: profile.ok_or("--profile is required")?,
        state_dir,
        code,
        imported,
        republish,
        json,
    }))
}

fn read_json(path: &Path, limit: usize) -> Result<Value> {
    let mut bytes = Vec::new();
    File::open(path)?
        .take((limit + 1) as u64)
        .read_to_end(&mut bytes)?;
    if bytes.len() > limit {
        return Err(format!("JSON exceeds {limit} bytes").into());
    }
    Ok(serde_json::from_slice(&bytes)?)
}

// Object ordering is explicit even if another workspace dependency enables
// serde_json's preserve_order feature. Array ordering and numeric values stay exact.
fn canonical(value: &Value, out: &mut Vec<u8>) -> Result<()> {
    match value {
        Value::Object(object) => {
            out.push(b'{');
            let mut keys: Vec<_> = object.keys().collect();
            keys.sort();
            for (index, key) in keys.iter().enumerate() {
                if index != 0 {
                    out.push(b',');
                }
                serde_json::to_writer(&mut *out, key)?;
                out.push(b':');
                canonical(&object[*key], out)?;
            }
            out.push(b'}');
        }
        Value::Array(array) => {
            out.push(b'[');
            for (index, item) in array.iter().enumerate() {
                if index != 0 {
                    out.push(b',');
                }
                canonical(item, out)?;
            }
            out.push(b']');
        }
        _ => serde_json::to_writer(out, value)?,
    }
    Ok(())
}

fn private_directory(path: &Path) -> Result<()> {
    fs::DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(path)?;
    let metadata = fs::symlink_metadata(path)?;
    if !metadata.is_dir() || metadata.permissions().mode() & 0o077 != 0 {
        return Err("state directory must be a real directory with mode 0700".into());
    }
    Ok(())
}

fn write_record(path: &Path, value: &Value) -> Result<()> {
    let parent = path.parent().ok_or("manifest has no parent")?;
    let mut temporary = tempfile::NamedTempFile::new_in(parent)?;
    serde_json::to_writer(&mut temporary, value)?;
    writeln!(temporary)?;
    temporary.as_file().sync_all()?;
    temporary.persist(path)?;
    File::open(parent)?.sync_all()?;
    Ok(())
}

fn archive(path: &Path, value: &Value) -> Result<()> {
    let parent = path.parent().ok_or("manifest has no parent")?;
    let mut file = tempfile::Builder::new()
        .prefix("previous-")
        .suffix(".json")
        .tempfile_in(parent)?;
    serde_json::to_writer(&mut file, value)?;
    writeln!(file)?;
    file.as_file().sync_all()?;
    let (_file, _path) = file.keep()?;
    File::open(parent)?.sync_all()?;
    Ok(())
}

fn timestamp() -> Result<u64> {
    Ok(SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs())
}

fn valid_code(code: &str) -> Result<()> {
    if code.len() != 36 || !code.bytes().all(|c| c.is_ascii_hexdigit() || c == b'-') {
        return Err("expected a 36-character Wootility profile code".into());
    }
    Ok(())
}

async fn request(
    client: &Client,
    method: Method,
    code: Option<&str>,
    body: Option<&[u8]>,
    deadline: Instant,
) -> Result<Value> {
    let remaining = deadline.saturating_duration_since(Instant::now());
    if remaining.is_zero() {
        return Err("overall network deadline exceeded".into());
    }
    let mut request = client
        .request(method, ENDPOINT)
        .timeout(remaining.min(Duration::from_secs(15)));
    if let Some(code) = code {
        request = request.query(&[("code", code)]);
    }
    if let Some(body) = body {
        request = request
            .header("Content-Type", "application/json")
            .body(body.to_vec());
    }
    // No automatic retries, including POST. Persisted intent guards reruns too.
    let mut response = request.send().await?;
    if !response.status().is_success() {
        return Err(format!(
            "Wooting service returned HTTP {}; no request was retried",
            response.status()
        )
        .into());
    }
    let mut bytes = Vec::new();
    while let Some(chunk) = response.chunk().await? {
        if bytes.len() + chunk.len() > MAX_RESPONSE {
            return Err("service response exceeds size limit".into());
        }
        bytes.extend_from_slice(&chunk);
    }
    let mut response: Value = serde_json::from_slice(&bytes)?;
    response
        .as_object_mut()
        .and_then(|object| object.remove("data"))
        .ok_or_else(|| "service response is missing data".into())
}

fn client() -> Result<Client> {
    Ok(Client::builder()
        .https_only(true)
        .redirect(reqwest::redirect::Policy::none())
        .retry(reqwest::retry::never())
        .connect_timeout(Duration::from_secs(5))
        .user_agent(concat!("wooting-profile-share/", env!("CARGO_PKG_VERSION")))
        .build()?)
}

async fn verify(client: &Client, code: &str, desired: &Value, deadline: Instant) -> Result<()> {
    valid_code(code)?;
    let mut actual = request(client, Method::GET, Some(code), None, deadline).await?;
    let object = actual
        .as_object_mut()
        .ok_or("retrieved profile must be an object")?;
    // This is the only demonstrated server-added field. Never discard unknown
    // differences or compare just selected modifier bindings.
    if let Some(guid) = object.remove("guid")
        && !guid.is_string()
    {
        return Err("unexpected server guid type".into());
    }
    let mut expected_bytes = Vec::new();
    let mut actual_bytes = Vec::new();
    canonical(desired, &mut expected_bytes)?;
    canonical(&actual, &mut actual_bytes)?;
    if expected_bytes != actual_bytes {
        return Err(
            "read-back differs from the complete desired profile; code was not verified".into(),
        );
    }
    Ok(())
}

async fn run(args: &Args) -> Result<Value> {
    let profile = read_json(&args.profile, MAX_PROFILE)?;
    validation::validate(&profile)?;
    let mut body = Vec::new();
    canonical(&profile, &mut body)?;
    let digest = format!("{}", base16ct::HexDisplay(&Sha256::digest(&body)));
    if args.action == "validate" {
        return Ok(
            json!({"status":"valid", "profile_sha256":digest, "adapter":ADAPTER,"validation_contract":validation::CONTRACT}),
        );
    }
    if args.action == "compare-import" {
        let imported = if let Some(path) = &args.imported {
            read_json(path, MAX_PROFILE)?
        } else {
            let code = args.code.as_deref().ok_or("missing comparison code")?;
            request(
                &client()?,
                Method::GET,
                Some(code),
                None,
                Instant::now() + Duration::from_secs(15),
            )
            .await?
        };
        validation::compare_import(&profile, &imported)?;
        return Ok(
            json!({"status":"import-content-matches", "profile_sha256":digest,
            "adapter":ADAPTER,"validation_contract":validation::CONTRACT,
            "scope":"supplied re-export content; app execution and keyboard persistence are not attested"}),
        );
    }
    private_directory(&args.state_dir)?;
    let lock = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .open(args.state_dir.join(".lock"))?;
    lock.try_lock_exclusive()
        .map_err(|error| format!("another operation may be active: {error}"))?;
    let manifest = args.state_dir.join(format!("{digest}.json"));
    let mut record = match read_json(&manifest, 2 * MAX_PROFILE) {
        Ok(value) => {
            if value["manifest_version"] != 1
                || value["adapter"] != ADAPTER
                || value["profile_sha256"] != digest
                || value["profile"] != profile
                || !["publishing", "pending", "verified"]
                    .iter()
                    .any(|s| value["status"] == *s)
            {
                return Err(
                    "existing manifest is incompatible or does not match the desired profile"
                        .into(),
                );
            }
            value
        }
        Err(error) => {
            if manifest.try_exists()? {
                return Err(error);
            }
            json!({"manifest_version":1,"adapter":ADAPTER,"profile_sha256":digest,
                "profile":profile,"created_at":timestamp()?,"status":"publishing"})
        }
    };
    record["validation_contract"] = json!(validation::CONTRACT);
    let client = client()?;
    let deadline = Instant::now() + Duration::from_secs(30);
    let code = if let Some(code) = &args.code {
        code.clone()
    } else if !args.republish && record["share_code"].is_string() {
        record["share_code"]
            .as_str()
            .ok_or("invalid cached code")?
            .to_owned()
    } else {
        if args.action != "publish" {
            return Err("no cached code; use publish or verify --code CODE".into());
        }
        if manifest.try_exists()? && !args.republish {
            return Err(format!("an earlier publication may have reached the service; no upload repeated. Recover with verify --code CODE, or intentionally publish --republish. Record: {}", manifest.display()).into());
        }
        if manifest.try_exists()? {
            archive(&manifest, &record)?;
        }
        record["status"] = json!("publishing");
        record["attempted_at"] = json!(timestamp()?);
        record
            .as_object_mut()
            .ok_or("manifest must be an object")?
            .remove("share_code");
        record
            .as_object_mut()
            .ok_or("manifest must be an object")?
            .remove("verified_at");
        write_record(&manifest, &record)?;
        eprintln!(
            "Uploading profile {:?} to Wooting's sharing service (SHA-256 {digest}).",
            profile["name"].as_str().ok_or("invalid name")?
        );
        let response = request(&client, Method::POST, None, Some(&body), deadline).await
            .map_err(|error| format!("publication outcome is unverified: {error}. Intent retained at {}; no POST will be automatically repeated", manifest.display()))?;
        let code = response
            .as_str()
            .ok_or("publication response did not contain a code; intent retained")?
            .to_owned();
        valid_code(&code)?;
        eprintln!("Received candidate code {code}; read-back verification is pending.");
        record["share_code"] = json!(code);
        record["status"] = json!("pending");
        write_record(&manifest, &record)?;
        code
    };
    verify(&client, &code, &profile, deadline).await.map_err(|error|
        format!("{error}. No new upload attempted during verification; local release record (if present): {}", manifest.display()))?;
    if record["share_code"]
        .as_str()
        .is_some_and(|previous| previous != code)
    {
        archive(&manifest, &record)?;
    }
    record["share_code"] = json!(code);
    record["status"] = json!("verified");
    record["verified_at"] = json!(timestamp()?);
    write_record(&manifest, &record)?;
    Ok(
        json!({"status":"verified","adapter":ADAPTER,"profile_sha256":digest,
        "share_code":code,"import_method":"Wootility My Profiles > Import Profile",
        "validation_contract":validation::CONTRACT,
        "manifest":manifest}),
    )
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> std::process::ExitCode {
    let result = async {
        let Some(args) = parse_args()? else {
            return Ok(());
        };
        let result = run(&args).await?;
        if args.json {
            println!("{}", serde_json::to_string_pretty(&result)?);
        } else {
            println!(
                "Profile SHA-256: {}",
                result["profile_sha256"].as_str().ok_or("missing hash")?
            );
            if let Some(code) = result["share_code"].as_str() {
                println!("Verified share code: {code}");
                println!(
                    "Import in Wootility, review the profile and slot, then Save to Keyboard."
                );
                println!(
                    "Release record: {}",
                    result["manifest"].as_str().ok_or("missing manifest")?
                );
            } else if result["status"] == "import-content-matches" {
                println!("Supplied imported content matches under {}. No app execution or hardware persistence is attested.", validation::CONTRACT);
            } else {
                println!("Profile matches {} for {ADAPTER}; no upload performed.", validation::CONTRACT);
            }
        }
        Ok::<(), Box<dyn Error>>(())
    }
    .await;
    match result {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("wooting-profile-share: {error}");
            std::process::ExitCode::FAILURE
        }
    }
}
