//! Commons featured-photo acquisition; Nix owns policy, Rust owns bounded state.
use fs2::FileExt;
use rand::seq::SliceRandom;
use regex::Regex;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    error::Error,
    fs::{self, OpenOptions},
    io::Write,
    os::unix::fs::{DirBuilderExt, PermissionsExt},
    path::{Path, PathBuf},
    time::{Duration, Instant},
};
type Result<T> = std::result::Result<T, Box<dyn Error>>;
#[derive(Debug)]
struct InvalidState;
impl std::fmt::Display for InvalidState {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("Commons discovery state is invalid; leaving collection unchanged")
    }
}
impl Error for InvalidState {}
struct Fetcher {
    policy: Value,
    deadline: Instant,
    directory: PathBuf,
    state_dir: PathBuf,
    width: u64,
    height: u64,
}
impl Fetcher {
    fn text(&self, key: &str) -> Result<&str> {
        self.policy[key]
            .as_str()
            .ok_or_else(|| format!("missing {key}").into())
    }
    fn number(&self, key: &str) -> Result<u64> {
        self.policy[key]
            .as_u64()
            .filter(|n| *n > 0)
            .ok_or_else(|| format!("invalid {key}").into())
    }
    async fn command(&self, args: &[&str]) -> Result<std::process::Output> {
        let remaining = self.deadline.saturating_duration_since(Instant::now());
        if remaining.is_zero() {
            return Err("Commons acquisition deadline exceeded".into());
        }
        Ok(nix_conf_process::run(
            tokio::process::Command::new(args[0]).args(&args[1..]),
            None,
            remaining,
        )
        .await?)
    }
    async fn transfer(&self, url: &str, path: &Path, page: bool, query: &[String]) -> Result<bool> {
        let remaining = self
            .deadline
            .saturating_duration_since(Instant::now())
            .as_secs_f64();
        if remaining <= 0.0 {
            return Err("Commons acquisition deadline exceeded".into());
        }
        let limit = if page {
            10_485_760
        } else {
            self.number("maxFileSizeBytes")?
        };
        let max_time = remaining.min(if page { 30.0 } else { 60.0 }).to_string();
        let retry_time = remaining.min(if page { 35.0 } else { 70.0 }).to_string();
        let limit_string = limit.to_string();
        let mut args = vec![
            "curl",
            "--fail",
            "--proto",
            "=https",
            "--tlsv1.2",
            "--connect-timeout",
            "10",
            "--max-time",
            &max_time,
            "--retry",
            if page { "2" } else { "1" },
            "--retry-delay",
            "2",
            "--retry-max-time",
            &retry_time,
            "--max-filesize",
            &limit_string,
            "--user-agent",
            self.text("userAgent")?,
            "--output",
            path.to_str().ok_or("invalid temporary path")?,
        ];
        if page {
            args.push("--get");
            for q in query {
                args.extend(["--data-urlencode", q]);
            }
        }
        args.push(url);
        Ok(self.command(&args).await?.status.success() && fs::metadata(path)?.len() <= limit)
    }
    fn geometry(&self, w: u64, h: u64) -> bool {
        let (w, h, tw, th) = (
            u128::from(w),
            u128::from(h),
            u128::from(self.width),
            u128::from(self.height),
        );
        w >= tw
            && h >= th
            && w * h <= 100_000_000
            && w * th * 5 >= h * tw * 4
            && w * th * 4 <= h * tw * 5
    }
    fn candidates(&self, page: &Value, route: &Value, category: &str) -> Result<Vec<Value>> {
        let rejected_categories = Regex::new(&format!(
            "(?i){}",
            self.policy["quality"]["rejectedCategories"]
                .as_str()
                .ok_or("invalid category regex")?
        ))?;
        let rejected_subjects = Regex::new(&format!(
            "(?i){}",
            self.policy["quality"]["rejectedSubjects"]
                .as_str()
                .ok_or("invalid subject regex")?
        ))?;
        let licenses = self.policy["licenses"]
            .as_array()
            .ok_or("invalid licenses")?;
        let pages: Vec<&Value> = match &page["query"]["pages"] {
            Value::Object(p) => p.values().collect(),
            Value::Array(p) => p.iter().collect(),
            _ => vec![],
        };
        let mut candidates = Vec::new();
        for p in pages {
            let image = &p["imageinfo"][0];
            let meta = &image["extmetadata"];
            if p["ns"] != 6
                || !meta["Assessments"]["value"]
                    .as_str()
                    .unwrap_or("")
                    .to_ascii_lowercase()
                    .split('|')
                    .any(|s| s == "featured")
            {
                continue;
            }
            let categories = meta["Categories"]["value"]
                .as_str()
                .unwrap_or("")
                .replace('_', " ");
            let categories: Vec<_> = categories.split('|').collect();
            let required = route["requireCollections"]
                .as_array()
                .map(Vec::as_slice)
                .unwrap_or(&[]);
            let excluded = route["excludeCollections"]
                .as_array()
                .map(Vec::as_slice)
                .unwrap_or(&[]);
            if !categories.contains(&category)
                || required
                    .iter()
                    .any(|r| !r.as_str().is_some_and(|s| categories.contains(&s)))
                || excluded
                    .iter()
                    .any(|r| r.as_str().is_some_and(|s| categories.contains(&s)))
                || categories.iter().any(|s| rejected_categories.is_match(s))
            {
                continue;
            }
            if !image["metadata"].as_array().is_some_and(|m| {
                m.iter().any(|v| {
                    v["name"] == "Model" && v["value"].as_str().is_some_and(|s| !s.is_empty())
                })
            }) {
                continue;
            }
            let subject = [
                p["title"].as_str(),
                meta["ImageDescription"]["value"].as_str(),
                meta["Categories"]["value"].as_str(),
            ]
            .into_iter()
            .flatten()
            .collect::<Vec<_>>()
            .join(" ")
            .to_ascii_lowercase();
            if rejected_subjects.is_match(&subject)
                || !licenses.contains(&meta["LicenseShortName"]["value"])
            {
                continue;
            }
            let Some(url) = image["url"]
                .as_str()
                .filter(|s| s.starts_with("https://upload.wikimedia.org/"))
            else {
                continue;
            };
            let (Some(w), Some(h), Some(size)) = (
                image["width"].as_u64(),
                image["height"].as_u64(),
                image["size"].as_u64(),
            ) else {
                continue;
            };
            if !self.geometry(w, h)
                || size == 0
                || size > self.number("maxFileSizeBytes")?
                || !matches!(
                    image["mime"].as_str(),
                    Some("image/jpeg" | "image/png" | "image/tiff" | "image/webp")
                )
            {
                continue;
            }
            let Some(id) = p["pageid"].as_u64() else {
                continue;
            };
            candidates.push(json!({"id":id.to_string(),"title":p["title"],"url":url,"original_width":w,"original_height":h,"mime":image["mime"],"license":meta["LicenseShortName"]["value"],"metadata":meta,"discovery_category":category,"connection":"wikimediaCommons","wallpaper_categories":[format!("{}/{}",route["category"].as_str().ok_or("missing category")?,route["subcategory"].as_str().ok_or("missing subcategory")?)]}));
        }
        Ok(candidates)
    }
    fn save(&self, state: &Value) -> Result<()> {
        let mut file = tempfile::NamedTempFile::new_in(&self.state_dir)?;
        serde_json::to_writer(&mut file, state)?;
        writeln!(file)?;
        file.as_file().sync_all()?;
        file.persist(self.state_dir.join("commons-discovery.json"))?;
        Ok(())
    }
    fn remember(&self, state: &mut Value, id: &str) -> Result<()> {
        let seen = state["seen"].as_array_mut().ok_or("invalid seen state")?;
        if !seen.iter().any(|s| s == id) {
            seen.push(json!(id));
        }
        if seen.len() > 10000 {
            seen.drain(..seen.len() - 10000);
        }
        self.save(state)
    }
    async fn download(
        &self,
        mut candidate: Value,
        scratch: &Path,
        network_failure: &mut bool,
        state: &mut Value,
    ) -> Result<bool> {
        let original = scratch.join("original");
        let display = scratch.join("display.jpg");
        let path = original.to_str().ok_or("invalid scratch path")?;
        if !self
            .transfer(
                candidate["url"].as_str().ok_or("missing URL")?,
                &original,
                false,
                &[],
            )
            .await?
        {
            *network_failure = true;
            return Ok(false);
        }
        let mime = self
            .command(&["file", "--brief", "--mime-type", "--", path])
            .await?;
        if !mime.status.success()
            || !matches!(
                String::from_utf8_lossy(&mime.stdout).trim(),
                "image/jpeg" | "image/png" | "image/tiff" | "image/webp"
            )
        {
            return Ok(false);
        }
        let dimensions = self
            .command(&[
                "magick",
                "identify",
                "-ping",
                "-format",
                "%w %h %[orientation]\n",
                "--",
                path,
            ])
            .await?;
        if !dimensions.status.success() {
            return Ok(false);
        }
        let dimensions = String::from_utf8_lossy(&dimensions.stdout);
        let parts: Vec<_> = dimensions.trim_end_matches('\n').split(' ').collect();
        if parts.len() != 3 || !parts[2].bytes().all(|b| b.is_ascii_alphabetic()) {
            return Ok(false);
        }
        let (Ok(mut w), Ok(mut h)) = (parts[0].parse::<u64>(), parts[1].parse::<u64>()) else {
            return Ok(false);
        };
        if ["LeftTop", "RightTop", "RightBottom", "LeftBottom"].contains(&parts[2]) {
            std::mem::swap(&mut w, &mut h);
        }
        if !self.geometry(w, h) {
            return Ok(false);
        }
        let resize = format!("{}x{}^", self.width, self.height);
        let extent = format!("{}x{}", self.width, self.height);
        if !self
            .command(&[
                "magick",
                "-limit",
                "memory",
                "256MiB",
                "-limit",
                "map",
                "512MiB",
                "-limit",
                "disk",
                "1GiB",
                path,
                "-auto-orient",
                "-colorspace",
                "sRGB",
                "-resize",
                &resize,
                "-gravity",
                "center",
                "-extent",
                &extent,
                "-strip",
                "-sampling-factor",
                "4:4:4",
                "-quality",
                "95",
                display.to_str().ok_or("invalid display path")?,
            ])
            .await?
            .status
            .success()
        {
            return Ok(false);
        }
        let output = self
            .command(&[
                "magick",
                "identify",
                "-ping",
                "-format",
                "%w %h",
                "--",
                display.to_str().ok_or("invalid display path")?,
            ])
            .await?;
        if !output.status.success()
            || output.stdout != format!("{} {}", self.width, self.height).as_bytes()
        {
            return Ok(false);
        }
        let checksum = format!(
            "{}",
            base16ct::HexDisplay(&Sha256::digest(fs::read(&display)?))
        );
        let id = candidate["id"].as_str().ok_or("invalid id")?.to_owned();
        let destination = self.directory.join(format!(
            "wikimedia-commons-{id}-{}x{}-{checksum}.jpg",
            self.width, self.height
        ));
        let metadata = json!({"source":"Wikimedia Commons featured photography","source_id":id,"source_page":format!("https://commons.wikimedia.org/?curid={id}"),"retrieved_at":time::OffsetDateTime::now_utc().format(&time::format_description::well_known::Rfc3339)?,"sha256":checksum,"width":self.width,"height":self.height,"conversion":"Centered crop and downsample to sRGB JPEG"});
        candidate
            .as_object_mut()
            .ok_or("invalid candidate")?
            .extend(metadata.as_object().ok_or("invalid metadata")?.clone());
        let sidecar = PathBuf::from(format!("{}.json", destination.display()));
        let mut file = tempfile::NamedTempFile::new_in(&self.directory)?;
        serde_json::to_writer(&mut file, &candidate)?;
        writeln!(file)?;
        file.as_file().sync_all()?;
        file.persist(&sidecar)?;
        fs::set_permissions(&display, fs::Permissions::from_mode(0o600))?;
        if let Err(e) = fs::rename(&display, &destination) {
            let _cleanup_result = fs::remove_file(sidecar);
            return Err(e.into());
        }
        self.remember(state, &id)?;
        println!(
            "Added Commons photograph {id} ({}x{}).",
            self.width, self.height
        );
        Ok(true)
    }
    fn prune(&self) -> Result<()> {
        let current = fs::read_to_string(self.state_dir.join("current")).unwrap_or_default();
        let mut files = Vec::new();
        for e in fs::read_dir(&self.directory)? {
            let e = e?;
            let name = e.file_name();
            let name = name.to_string_lossy();
            if e.file_type()?.is_file()
                && name.starts_with("wikimedia-commons-")
                && name.ends_with(".jpg")
            {
                files.push((e.metadata()?.modified()?, e.path()));
            }
        }
        files.sort();
        let excess = files
            .len()
            .saturating_sub(usize::try_from(self.number("maxImages")?)?);
        for (_, path) in files
            .into_iter()
            .filter(|(_, p)| p.as_os_str() != std::ffi::OsStr::new(current.trim_end_matches('\n')))
            .take(excess)
        {
            fs::remove_file(&path)?;
            match fs::remove_file(format!("{}.json", path.display())) {
                Ok(()) => (),
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => (),
                Err(e) => return Err(e.into()),
            }
        }
        Ok(())
    }
    async fn discover(&self, routes: &[Value]) -> Result<()> {
        for path in [&self.directory, &self.state_dir] {
            fs::DirBuilder::new()
                .recursive(true)
                .mode(0o700)
                .create(path)?;
            fs::set_permissions(path, fs::Permissions::from_mode(0o700))?;
        }
        let lock = OpenOptions::new()
            .create(true)
            .append(true)
            .open(self.state_dir.join("commons-fetch.lock"))?;
        if let Err(e) = lock.try_lock_exclusive() {
            if e.kind() == std::io::ErrorKind::WouldBlock {
                return Ok(());
            }
            return Err(e.into());
        }
        let state_path = self.state_dir.join("commons-discovery.json");
        let mut state: Value = match fs::read(state_path) {
            Ok(s) => serde_json::from_slice(&s).map_err(|_| InvalidState)?,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                json!({"version":1,"nextCategory":0,"cursors":{},"seen":[]})
            }
            Err(e) => return Err(e.into()),
        };
        if state["version"] != 1
            || state["nextCategory"].as_u64().is_none()
            || !state["cursors"].is_object()
            || !state["seen"].is_array()
        {
            return Err(InvalidState.into());
        }
        let index = usize::try_from(
            state["nextCategory"]
                .as_u64()
                .ok_or("invalid category index")?
                % u64::try_from(routes.len())?,
        )?;
        let route = &routes[index];
        let category = route["collection"].as_str().ok_or("invalid collection")?;
        let key = if route["requireCollections"]
            .as_array()
            .is_none_or(Vec::is_empty)
        {
            category.to_owned()
        } else {
            format!(
                "{}/{}:{category}",
                route["category"].as_str().ok_or("invalid category")?,
                route["subcategory"].as_str().ok_or("invalid subcategory")?
            )
        };
        state["nextCategory"] = json!(index + 1);
        self.save(&state)?;
        let scratch = tempfile::Builder::new()
            .prefix(".commons-")
            .tempdir_in(&self.directory)?;
        let mut attempts = 0;
        let mut failure = false;
        let mut accepted = false;
        for _ in 0..self.number("maxCandidatePages")? {
            if attempts >= self.number("maxCandidateDownloads")? {
                break;
            }
            let mut query = vec![
                "action=query".into(),
                "generator=categorymembers".into(),
                format!("gcmtitle=Category:{category}"),
                "gcmnamespace=6".into(),
                "gcmtype=file".into(),
                "gcmsort=timestamp".into(),
                "gcmdir=older".into(),
                "gcmlimit=50".into(),
                "prop=imageinfo".into(),
                "iiprop=url|size|mime|extmetadata|metadata".into(),
                "format=json".into(),
            ];
            if let Some(cursor) = state["cursors"][&key].as_object() {
                for (k, v) in cursor {
                    query.push(format!(
                        "{k}={}",
                        v.as_str().ok_or("invalid continuation token")?
                    ));
                }
            }
            let page_path = scratch.path().join("page.json");
            if !self
                .transfer(
                    "https://commons.wikimedia.org/w/api.php",
                    &page_path,
                    true,
                    &query,
                )
                .await?
            {
                failure = true;
                break;
            }
            let page: Value = serde_json::from_slice(&fs::read(page_path)?)?;
            if !page.is_object()
                || page.get("error").is_some()
                || (page.get("query").is_none() && page.get("batchcomplete").is_none())
            {
                if page["error"]["code"] == "badcontinue" {
                    state["cursors"][&key] = json!({});
                    self.save(&state)?;
                }
                failure = true;
                break;
            }
            let mut candidates = self.candidates(&page, route, category)?;
            candidates.shuffle(&mut rand::rng());
            for candidate in candidates {
                let id = candidate["id"].as_str().ok_or("missing id")?;
                if state["seen"]
                    .as_array()
                    .ok_or("invalid seen")?
                    .iter()
                    .any(|s| s == id)
                {
                    continue;
                }
                let prefix = format!("wikimedia-commons-{id}-{}x{}-", self.width, self.height);
                let exists = fs::read_dir(&self.directory)?
                    .filter_map(std::result::Result::ok)
                    .any(|e| {
                        let n = e.file_name();
                        let n = n.to_string_lossy();
                        n.starts_with(&prefix) && n.ends_with(".jpg")
                    });
                if exists {
                    self.remember(&mut state, id)?;
                    continue;
                }
                if attempts >= self.number("maxCandidateDownloads")? {
                    break;
                }
                attempts += 1;
                if self
                    .download(candidate, scratch.path(), &mut failure, &mut state)
                    .await?
                {
                    accepted = true;
                    break;
                }
            }
            let continuation = page.get("continue").cloned().unwrap_or(json!({}));
            if !continuation.is_object() {
                return Err("invalid continuation".into());
            }
            if !failure || accepted {
                state["cursors"][&key] = continuation.clone();
                self.save(&state)?;
            }
            if accepted || failure || continuation == json!({}) {
                break;
            }
        }
        if accepted {
            self.prune()?;
            return Ok(());
        }
        if failure {
            return Err("Commons transfer or API failed; cursor preserved".into());
        }
        println!(
            "No unseen qualifying photographs in {category}; discovery will continue next run."
        );
        Ok(())
    }
}
async fn run() -> Result<()> {
    let deadline = Instant::now() + Duration::from_secs(240);
    let policy: Value = serde_json::from_slice(&fs::read(
        std::env::args_os().nth(1).ok_or("policy required")?,
    )?)?;
    let policy_command = policy["policyCommand"]
        .as_str()
        .ok_or("missing policy command")?;
    let out = nix_conf_process::run(
        tokio::process::Command::new(policy_command).args(["plan", "wikimediaCommons"]),
        None,
        deadline.saturating_duration_since(Instant::now()),
    )
    .await?;
    if !out.status.success() {
        return Err("invalid wallpaper preferences".into());
    }
    let routes: Value = serde_json::from_slice(&out.stdout)?;
    let routes = routes.as_array().ok_or("invalid plan")?;
    if routes.is_empty() {
        return Ok(());
    }
    let fetcher = Fetcher {
        directory: PathBuf::from(policy["directory"].as_str().ok_or("missing directory")?),
        state_dir: PathBuf::from(policy["state"].as_str().ok_or("missing state")?),
        width: policy["width"]
            .as_u64()
            .filter(|n| *n > 0)
            .ok_or("invalid width")?,
        height: policy["height"]
            .as_u64()
            .filter(|n| *n > 0)
            .ok_or("invalid height")?,
        policy,
        deadline,
    };
    fetcher.discover(routes).await
}
#[tokio::main(flavor = "current_thread")]
async fn main() -> std::process::ExitCode {
    match run().await {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("Commons wallpaper acquisition: {e}");
            std::process::ExitCode::from(if e.downcast_ref::<InvalidState>().is_some() {
                65
            } else {
                1
            })
        }
    }
}
