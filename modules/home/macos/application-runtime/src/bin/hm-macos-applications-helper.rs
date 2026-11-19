//! Reconcile copied apps without resetting unrelated Launch Services registrations.
use clap::Parser;
use fs2::FileExt;
use macos_application_tools::{Result, checked, fail};
use regex::Regex;
use serde_json::{Value, json};
use std::{
    collections::{BTreeMap, HashSet},
    fs::{self, DirBuilder, OpenOptions},
    io::Write,
    os::unix::fs::DirBuilderExt,
    path::{Path, PathBuf},
};
const LSREGISTER: &str = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister";
#[derive(Parser)]
#[command(about = "Reconcile copied macOS apps without resetting unrelated registrations.")]
struct Args {
    #[arg(long)]
    apps_dir: Option<PathBuf>,
    #[arg(long)]
    legacy_dir: Option<PathBuf>,
    #[arg(long)]
    state_dir: Option<PathBuf>,
    #[arg(long)]
    query_script: PathBuf,
    #[arg(long,conflicts_with_all=["check","registered_paths"])]
    dry_run: bool,
    #[arg(long, conflicts_with = "registered_paths")]
    check: bool,
    #[arg(long,num_args=1..)]
    registered_paths: Vec<String>,
}
struct App {
    path: PathBuf,
    identifier: String,
}
fn path_text(path: &Path) -> Result<&str> {
    path.to_str().ok_or_else(|| "Invalid native path".into())
}
fn store_app() -> Result<Regex> {
    Ok(Regex::new(r"^/nix/store/[^/]+/Applications/[^/]+\.app$")?)
}
fn disabled(dump: &str) -> Result<HashSet<String>> {
    let block = Regex::new(r"(?m)^-{20,}\s*$")?;
    let path = Regex::new(r"(?m)^path:\s+(.+?)\s+\(0x[0-9a-fA-F]+\)\s*$")?;
    let flags = Regex::new(r"(?m)^bundle flags:\s+(.+)$")?;
    let store = store_app()?;
    let mut result = HashSet::new();
    for record in block.split(dump) {
        let (Some(p), Some(f)) = (path.captures(record), flags.captures(record)) else {
            continue;
        };
        if !f[1].split_whitespace().any(|v| v == "launch-disabled") {
            continue;
        }
        let bundle = Path::new(&p[1]);
        let recovery = bundle.extension().is_some_and(|v| v == "app")
            && bundle.parent().and_then(Path::file_name).is_some_and(|v| {
                let name = v.to_string_lossy();
                name.starts_with(".hm-app-update-") && name.ends_with(".noindex")
            });
        if store.is_match(&p[1]) || recovery {
            result.insert(p[1].to_owned());
        }
    }
    Ok(result)
}
async fn paths(script: &Path, identifiers: &[String]) -> Result<BTreeMap<String, Vec<String>>> {
    let mut args = vec!["-l", "JavaScript", path_text(script)?];
    args.extend(identifiers.iter().map(String::as_str));
    let data: Value = serde_json::from_slice(&checked("/usr/bin/osascript", &args).await?.stdout)?;
    let disabled = disabled(&String::from_utf8(
        checked(LSREGISTER, &["-dump"]).await?.stdout,
    )?)?;
    let mut result = BTreeMap::new();
    for id in identifiers {
        let available = data[id]["available"]
            .as_array()
            .ok_or("Invalid application URL inventory")?;
        let mut values = vec![];
        for p in available {
            let p = p.as_str().ok_or("Invalid application URL inventory")?;
            if !disabled.contains(p) && Path::new(p).exists() {
                values.push(p.to_owned());
            }
        }
        result.insert(id.clone(), values);
    }
    Ok(result)
}
fn identifier(path: &Path) -> Result<String> {
    let plist = plist::Value::from_file(path.join("Contents/Info.plist"))?;
    plist
        .as_dictionary()
        .and_then(|d| d.get("CFBundleIdentifier"))
        .and_then(plist::Value::as_string)
        .filter(|v| !v.is_empty())
        .map(str::to_owned)
        .ok_or_else(|| format!("Application has no bundle identifier: {}", path.display()).into())
}
fn applications(directory: &Path) -> Result<Vec<App>> {
    if directory.is_symlink() || !directory.is_dir() {
        return fail(&format!(
            "Expected a real copied application directory: {}",
            directory.display()
        ));
    }
    let mut entries = fs::read_dir(directory)?
        .map(|e| e.map(|e| e.path()))
        .collect::<std::io::Result<Vec<_>>>()?;
    entries.sort();
    let mut ids = HashSet::new();
    let mut result = vec![];
    for path in entries
        .into_iter()
        .filter(|p| p.extension().is_some_and(|e| e == "app"))
    {
        if path.is_symlink() || !path.is_dir() {
            return fail(&format!(
                "Expected a copied application bundle: {}",
                path.display()
            ));
        }
        let id = identifier(&path)?;
        if !ids.insert(id.clone()) {
            return fail(&format!(
                "Multiple copied bundles share an identifier: {id}"
            ));
        }
        result.push(App {
            path,
            identifier: id,
        });
    }
    Ok(result)
}
fn legacy(apps: &[App], directory: &Path) -> Result<Vec<PathBuf>> {
    let store = store_app()?;
    let mut result = vec![];
    for app in apps {
        let candidate = directory.join(app.path.file_name().ok_or("Missing bundle filename")?);
        if candidate == app.path || !candidate.is_symlink() {
            continue;
        }
        // A dangling link cannot name a verified obsolete bundle.
        let target = match candidate.canonicalize() {
            Ok(path) => path,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => continue,
            Err(e) => return Err(e.into()),
        };
        if store.is_match(path_text(&target)?)
            && target.is_dir()
            && identifier(&target)? == app.identifier
        {
            result.push(candidate);
        }
    }
    Ok(result)
}
fn archive(links: &[PathBuf], state: &Path) -> Result<()> {
    if links.is_empty() {
        return Ok(());
    }
    let backup = tempfile::Builder::new()
        .prefix("migration-")
        .tempdir_in(state)?
        .keep();
    for (index, link) in links.iter().enumerate() {
        let target = fs::read_link(link)?;
        let saved = backup.join(format!(
            "{index}-{}",
            link.file_name()
                .ok_or("Missing link name")?
                .to_string_lossy()
        ));
        let mut journal = OpenOptions::new()
            .create_new(true)
            .write(true)
            .open(backup.join(format!("{index}.json")))?;
        serde_json::to_writer(
            &mut journal,
            &json!({"original":link,"target":target,"saved":saved}),
        )?;
        writeln!(journal)?;
        journal.sync_all()?;
        if fs::read_link(link)? != target {
            return fail(&format!(
                "Legacy application link changed during migration: {}",
                link.display()
            ));
        }
        fs::rename(link, &saved)?;
        eprintln!(
            "Archived obsolete application link: {} -> {}",
            link.display(),
            saved.display()
        );
    }
    Ok(())
}
async fn reconcile(args: &Args, directory: &Path, legacy_dir: &Path, state: &Path) -> Result<()> {
    let apps = applications(directory)?;
    let ids = apps
        .iter()
        .map(|a| a.identifier.clone())
        .collect::<Vec<_>>();
    let before = paths(&args.query_script, &ids).await?;
    let links = legacy(&apps, legacy_dir)?;
    if !args.check {
        if args.dry_run {
            for link in &links {
                eprintln!("Would archive obsolete link: {}", link.display());
            }
        } else {
            archive(&links, state)?;
        }
        let store = store_app()?;
        for app in &apps {
            for path in &before[&app.identifier] {
                if store.is_match(path) {
                    if args.dry_run {
                        eprintln!("Would unregister: {path}");
                    } else {
                        checked(LSREGISTER, &["-u", path]).await?;
                    }
                }
            }
            if args.dry_run {
                eprintln!("Would register: {}", app.path.display());
            } else {
                checked(LSREGISTER, &["-f", path_text(&app.path)?]).await?;
            }
        }
    }
    if args.dry_run {
        return Ok(());
    }
    let after = paths(&args.query_script, &ids).await?;
    let store = store_app()?;
    for app in &apps {
        let paths = &after[&app.identifier];
        if !paths.iter().any(|p| Path::new(p) == app.path)
            || paths.iter().any(|p| store.is_match(p))
        {
            return fail(&format!(
                "Application registration did not converge: {}: {paths:?}",
                app.identifier
            ));
        }
    }
    eprintln!(
        "Verified {} canonical application registrations",
        apps.len()
    );
    if args.check && !links.is_empty() {
        return fail("Obsolete application symlinks remain");
    }
    Ok(())
}
async fn execute(args: Args) -> Result<()> {
    if !args.registered_paths.is_empty() {
        println!(
            "{}",
            serde_json::to_string(&paths(&args.query_script, &args.registered_paths).await?)?
        );
        return Ok(());
    }
    let directory = args
        .apps_dir
        .as_deref()
        .ok_or("--apps-dir, --legacy-dir and --state-dir are required for reconciliation")?;
    let legacy = args
        .legacy_dir
        .as_deref()
        .ok_or("--legacy-dir is required")?;
    let state = args.state_dir.as_deref().ok_or("--state-dir is required")?;
    let _lock = if !args.dry_run && !args.check {
        DirBuilder::new()
            .recursive(true)
            .mode(0o700)
            .create(state)?;
        let lock = OpenOptions::new()
            .create(true)
            .write(true)
            .truncate(true)
            .open(state.join("activation.lock"))?;
        lock.lock_exclusive()?;
        Some(lock)
    } else {
        None
    };
    reconcile(&args, directory, legacy, state).await
}
#[tokio::main(flavor = "current_thread")]
async fn main() {
    if let Err(error) = execute(Args::parse()).await {
        eprintln!("Application registration failed: {error}");
        std::process::exit(1);
    }
}
