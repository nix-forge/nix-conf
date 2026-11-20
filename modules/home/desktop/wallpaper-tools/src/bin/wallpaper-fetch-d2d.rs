//! Bounded acquisition of licensed observational ESA Data2Dome images.
use fs2::FileExt;
use rand::seq::SliceRandom;
use regex::Regex;
use scraper::{Html, Selector};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    collections::{BTreeSet, HashMap, HashSet},
    error::Error,
    fs::{self, OpenOptions},
    io::{Read, Write},
    os::unix::fs::{DirBuilderExt, MetadataExt, PermissionsExt},
    path::{Path, PathBuf},
    time::{Duration, Instant},
};
type Result<T> = std::result::Result<T, Box<dyn Error>>;
const LIMIT: u64 = 150 * 1024 * 1024;
fn truthy(value: &Value) -> bool {
    match value {
        Value::Null => false,
        Value::Bool(value) => *value,
        Value::String(value) => !value.is_empty(),
        Value::Array(value) => !value.is_empty(),
        Value::Object(value) => !value.is_empty(),
        Value::Number(value) => value.as_f64().is_some_and(|value| value != 0.0),
    }
}

struct Provider {
    host: &'static str,
    prefix: &'static str,
}
struct Args {
    connection: String,
    plan: PathBuf,
    directory: PathBuf,
    state: PathBuf,
    width: u64,
    height: u64,
    max_images: usize,
    max_pages: usize,
    max_downloads: usize,
}
struct Fetcher {
    deadline: Instant,
    provider: Provider,
    args: Args,
    title: Regex,
    description: Regex,
    id: Regex,
    strip: Regex,
    visible: Regex,
}
impl Fetcher {
    fn remaining(&self, max: u64) -> Result<Duration> {
        let left = self.deadline.saturating_duration_since(Instant::now());
        if left.is_zero() {
            return Err("astronomy acquisition exceeded its four-minute budget".into());
        }
        Ok(left.min(Duration::from_secs(max)))
    }
    async fn command(&self, args: &[String], max: u64) -> Result<std::process::Output> {
        Ok(nix_conf_process::run(
            tokio::process::Command::new(&args[0]).args(&args[1..]),
            None,
            self.remaining(max)?,
        )
        .await?)
    }
    async fn fetch(&self, url: &str, path: &Path, limit: u64) -> Result<()> {
        let remaining = self.remaining(145)?.as_secs_f64();
        let args = vec![
            "curl".into(),
            "--fail".into(),
            "--silent".into(),
            "--show-error".into(),
            "--proto".into(),
            "=https".into(),
            "--tlsv1.2".into(),
            "--connect-timeout".into(),
            "10".into(),
            "--max-time".into(),
            remaining.min(60.0).to_string(),
            "--retry".into(),
            "1".into(),
            "--retry-delay".into(),
            "2".into(),
            "--retry-max-time".into(),
            remaining.min(70.0).to_string(),
            "--max-filesize".into(),
            limit.to_string(),
            "--user-agent".into(),
            "desktop-wallpaper/1.0 (ESA Data2Dome landscape image client)".into(),
            "--output".into(),
            path.to_str().ok_or("non-UTF8 cache path")?.into(),
            url.into(),
        ];
        if !self.command(&args, 145).await?.status.success() {
            return Err("provider transfer failed".into());
        }
        if fs::metadata(path)?.len() > limit {
            return Err("provider exceeded transfer limit".into());
        }
        Ok(())
    }
    fn feed(&self) -> String {
        format!("https://{}/images/d2d/", self.provider.host)
    }
    fn feed_url(&self, value: &str) -> bool {
        let Ok(url) = url::Url::parse(value) else {
            return false;
        };
        if !value.starts_with(&self.feed())
            || url.scheme() != "https"
            || url.host_str() != Some(self.provider.host)
            || url.port().is_some()
            || !url.username().is_empty()
            || url.password().is_some()
            || url.path() != "/images/d2d/"
            || url.fragment().is_some()
        {
            return false;
        }
        let query: Vec<_> = url.query_pairs().collect();
        query.is_empty()
            || (query.len() == 1
                && query[0].0 == "page"
                && query[0].1.bytes().all(|b| b.is_ascii_digit())
                && query[0].1.parse::<u64>().is_ok_and(|v| v > 0 && v <= 10000))
    }
    fn geometry(&self, width: u64, height: u64) -> bool {
        let (w, h, tw, th) = (
            u128::from(width),
            u128::from(height),
            u128::from(self.args.width),
            u128::from(self.args.height),
        );
        width >= self.args.width
            && height >= self.args.height
            && w * h <= 100_000_000
            && w * th * 5 >= h * tw * 4
            && w * th * 4 <= h * tw * 5
    }
    fn resource<'a>(&self, item: &'a Value) -> Option<&'a Value> {
        if item["Rights"] != "Creative Commons Attribution 4.0 International License"
            || !truthy(&item["Credit"])
            || item["Priority"].as_f64().unwrap_or(0.0) < 80.0
        {
            return None;
        }
        let id = item["ID"].as_str()?;
        if !self.id.is_match(id)
            || item["ReferenceURL"] != format!("https://{}/images/{id}/", self.provider.host)
            || self.title.is_match(item["Title"].as_str()?)
        {
            return None;
        }
        let description = self
            .strip
            .replace_all(item["Description"].as_str().unwrap_or(""), "");
        if self
            .visible
            .captures(&description)
            .and_then(|c| c.get(1))
            .is_some_and(|s| self.description.is_match(s.as_str()))
        {
            return None;
        }
        for asset in item["Assets"].as_array()? {
            if asset["MediaType"] != "Image"
                || !truthy(&asset["ObservationData"]["Facility"])
                || !truthy(&asset["ObservationData"]["Instrument"])
            {
                continue;
            }
            let Some(resources) = asset["Resources"].as_array() else {
                continue;
            };
            for resource in resources {
                if resource["ResourceType"] != "Large"
                    || resource["MediaType"] != "Image"
                    || resource["ProjectionType"] != "Observation"
                    || resource["URL"]
                        != format!(
                            "https://cdn.{}/archives/images/large/{id}.jpg",
                            self.provider.host
                        )
                {
                    continue;
                }
                let Some(dimensions) = resource["Dimensions"].as_array() else {
                    continue;
                };
                let [width, height] = dimensions.as_slice() else {
                    continue;
                };
                let (Some(width), Some(height), Some(size)) = (
                    width.as_u64(),
                    height.as_u64(),
                    resource["FileSize"].as_u64(),
                ) else {
                    continue;
                };
                if width > 0
                    && height > 0
                    && size > 0
                    && size <= LIMIT
                    && self.geometry(width, height)
                {
                    return Some(resource);
                }
            }
        }
        None
    }
    fn categories(&self, text: &str) -> Result<(BTreeSet<String>, bool)> {
        let html = Html::parse_document(text);
        let selector = |s| Selector::parse(s).map_err(|_| "invalid built-in HTML selector");
        let table = selector("table[aria-describedby=\"About the Object\"]")?;
        let row = selector("tr")?;
        let heading = selector("th")?;
        let links = selector("a")?;
        let mut categories = BTreeSet::new();
        let mut excluded = false;
        for table in html.select(&table) {
            for row in table.select(&row) {
                if !row
                    .select(&heading)
                    .any(|h| h.text().collect::<String>().trim() == "Category:")
                {
                    continue;
                }
                for link in row.select(&links) {
                    if let Some(name) = link
                        .value()
                        .attr("href")
                        .and_then(|s| s.strip_prefix("/images/archive/category/"))
                        .and_then(|s| s.strip_suffix('/'))
                    {
                        match name {
                            "graphics" | "illustrations" | "spacecraft" | "spectroscopy"
                            | "launch" => excluded = true,
                            "nebulae" | "galaxies" | "stars" => {
                                categories.insert(name.into());
                            }
                            "clusters" => {
                                categories.insert("stars".into());
                            }
                            "solarsystem" => {
                                categories.insert("solar-system".into());
                            }
                            _ => {}
                        }
                    }
                }
            }
        }
        Ok((categories, excluded))
    }
    async fn render(&self, original: &Path, display: &Path) -> Result<bool> {
        let original = original.to_str().ok_or("invalid image path")?;
        let display = display.to_str().ok_or("invalid image path")?;
        let args = [
            "magick",
            "identify",
            "-ping",
            "-format",
            "%w %h %[orientation] %m",
            original,
        ]
        .map(str::to_owned);
        let output = self.command(&args, 30).await?;
        if !output.status.success() {
            return Ok(false);
        }
        let text = String::from_utf8(output.stdout)?;
        let fields: Vec<_> = text.split_whitespace().collect();
        let [width, height, orientation, format] = fields.as_slice() else {
            return Ok(false);
        };
        if !["JPEG", "PNG", "TIFF", "WEBP"].contains(format) {
            return Ok(false);
        }
        let (mut width, mut height) = (width.parse()?, height.parse()?);
        if ["LeftTop", "RightTop", "RightBottom", "LeftBottom"].contains(orientation) {
            std::mem::swap(&mut width, &mut height);
        }
        if !self.geometry(width, height) {
            return Ok(false);
        }
        let args = [
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
            original,
            "-auto-orient",
            "-colorspace",
            "sRGB",
            "-resize",
            &format!("{}x{}^", self.args.width, self.args.height),
            "-gravity",
            "center",
            "-extent",
            &format!("{}x{}", self.args.width, self.args.height),
            "-strip",
            "-sampling-factor",
            "4:4:4",
            "-quality",
            "95",
            display,
        ]
        .map(str::to_owned);
        Ok(self.command(&args, 120).await?.status.success())
    }
    fn load(&self, path: &Path) -> Result<Value> {
        if !path.exists() {
            return Ok(json!({"version":1,"cursor":self.feed(),"seen":[]}));
        }
        let state: Value = serde_json::from_slice(&fs::read(path)?)?;
        if state["version"] != 1
            || !state["cursor"].as_str().is_some_and(|s| self.feed_url(s))
            || !state["seen"]
                .as_array()
                .is_some_and(|a| a.iter().all(Value::is_string))
        {
            return Err("invalid astronomy discovery state".into());
        }
        Ok(state)
    }
    fn save(&self, path: &Path, state: &Value) -> Result<()> {
        let mut file = tempfile::NamedTempFile::new_in(path.parent().ok_or("invalid state path")?)?;
        serde_json::to_writer(&mut file, state)?;
        writeln!(file)?;
        file.as_file().sync_all()?;
        file.persist(path)?;
        Ok(())
    }
    fn seen(state: &mut Value, id: &str) -> Result<()> {
        let seen = state["seen"].as_array_mut().ok_or("invalid seen list")?;
        seen.push(Value::String(id.into()));
        if seen.len() > 10000 {
            seen.drain(..seen.len() - 10000);
        }
        Ok(())
    }
    fn prune(&self) -> Result<()> {
        let current = match fs::read_to_string(self.args.state.join("current")) {
            Ok(s) => s.trim().to_owned(),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => String::new(),
            Err(e) => return Err(e.into()),
        };
        let mut images = Vec::new();
        for image in fs::read_dir(&self.args.directory)? {
            let image = image?;
            let name = image.file_name();
            let name = name.to_string_lossy();
            if name.starts_with(self.provider.prefix) && name.ends_with(".jpg") {
                images.push((
                    image.metadata()?.mtime_nsec(),
                    image.metadata()?.mtime(),
                    image.path(),
                ));
            }
        }
        images.sort_by(|a, b| (a.1, a.0, &a.2).cmp(&(b.1, b.0, &b.2)));
        let mut excess = images.len().saturating_sub(self.args.max_images);
        for (_, _, image) in images {
            if excess == 0 {
                break;
            }
            if image.as_os_str() != std::ffi::OsStr::new(&current) {
                fs::remove_file(&image)?;
                let sidecar = PathBuf::from(format!("{}.json", image.display()));
                match fs::remove_file(sidecar) {
                    Ok(()) => {}
                    Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
                    Err(e) => return Err(e.into()),
                }
                excess -= 1;
            }
        }
        Ok(())
    }
    async fn discover(&self, enabled: HashSet<String>) -> Result<()> {
        let state_path = self
            .args
            .state
            .join(format!("{}discovery.json", self.provider.prefix));
        let mut state = self.load(&state_path)?;
        let scratch = tempfile::Builder::new()
            .prefix(".d2d-")
            .tempdir_in(&self.args.directory)?;
        let scratch = scratch.path();
        let mut inspections = 0;
        for _ in 0..self.args.max_pages {
            let page_file = scratch.join("page.json");
            self.fetch(
                state["cursor"].as_str().ok_or("invalid cursor")?,
                &page_file,
                10 * 1024 * 1024,
            )
            .await?;
            let page: Value = serde_json::from_slice(&fs::read(page_file)?)?;
            let mut candidates = page["Collections"]
                .as_array()
                .filter(|a| a.len() <= 100)
                .ok_or("invalid Data2Dome feed response")?
                .clone();
            let next = page
                .get("Next")
                .filter(|v| !v.is_null() && v.as_str() != Some(""))
                .map(|v| v.as_str().ok_or("invalid continuation URL"))
                .transpose()?
                .map(str::to_owned)
                .unwrap_or_else(|| self.feed());
            if !self.feed_url(&next) {
                return Err("invalid Data2Dome continuation URL".into());
            }
            candidates.shuffle(&mut rand::rng());
            for item in candidates {
                let Some(resource) = self.resource(&item) else {
                    continue;
                };
                let id = item["ID"].as_str().ok_or("invalid source identifier")?;
                if state["seen"]
                    .as_array()
                    .ok_or("invalid seen state")?
                    .iter()
                    .any(|v| v == id)
                {
                    continue;
                }
                let prefix = format!(
                    "{}{id}-{}x{}-",
                    self.provider.prefix, self.args.width, self.args.height
                );
                let mut cached = false;
                for file in fs::read_dir(&self.args.directory)? {
                    let name = file?.file_name();
                    let name = name.to_string_lossy();
                    if name.starts_with(&prefix) && name.ends_with(".jpg") {
                        cached = true;
                        break;
                    }
                }
                if cached {
                    Self::seen(&mut state, id)?;
                    continue;
                }
                if inspections >= self.args.max_downloads {
                    break;
                }
                inspections += 1;
                let detail = scratch.join("detail.html");
                self.fetch(
                    item["ReferenceURL"].as_str().ok_or("missing source page")?,
                    &detail,
                    2 * 1024 * 1024,
                )
                .await?;
                let (categories, excluded) = self.categories(&fs::read_to_string(detail)?)?;
                if excluded || !categories.iter().any(|s| enabled.contains(s)) {
                    continue;
                }
                let original = scratch.join("original");
                let display = scratch.join("display.jpg");
                self.fetch(
                    resource["URL"].as_str().ok_or("missing media URL")?,
                    &original,
                    LIMIT,
                )
                .await?;
                if !self.render(&original, &display).await? {
                    eprintln!("Skipping an invalid astronomy image.");
                    continue;
                }
                let mut hash = Sha256::new();
                let mut input = fs::File::open(&display)?;
                let mut buffer = [0; 64 * 1024];
                loop {
                    let size = input.read(&mut buffer)?;
                    if size == 0 {
                        break;
                    }
                    hash.update(&buffer[..size]);
                }
                let checksum = format!("{}", base16ct::HexDisplay(&hash.finalize()));
                let destination = self.args.directory.join(format!("{prefix}{checksum}.jpg"));
                let sidecar = PathBuf::from(format!("{}.json", destination.display()));
                let metadata = json!({"connection":self.args.connection,"wallpaper_categories":categories.iter().map(|s|format!("space/{s}")).collect::<Vec<_>>(),"source":item.get("Creator").cloned().unwrap_or_else(||Value::String(self.args.connection.clone())),"source_id":id,"source_page":item["ReferenceURL"],"title":item["Title"],"credit":item["Credit"],"license":"CC BY 4.0","license_url":"https://creativecommons.org/licenses/by/4.0/","url":resource["URL"],"original_width":resource["Dimensions"][0],"original_height":resource["Dimensions"][1],"width":self.args.width,"height":self.args.height,"sha256":checksum,"retrieved_at":time::OffsetDateTime::now_utc().format(&time::format_description::well_known::Rfc3339)?,"conversion":"Centered crop and downsample to sRGB JPEG"});
                let mut metadata_file = tempfile::NamedTempFile::new_in(scratch)?;
                serde_json::to_writer(&mut metadata_file, &metadata)?;
                writeln!(metadata_file)?;
                metadata_file.as_file().sync_all()?;
                fs::set_permissions(&display, fs::Permissions::from_mode(0o600))?;
                let publish = (|| -> Result<()> {
                    metadata_file.persist(&sidecar)?;
                    fs::rename(&display, &destination)?;
                    Self::seen(&mut state, id)?;
                    state["cursor"] = Value::String(next.clone());
                    self.save(&state_path, &state)?;
                    Ok(())
                })();
                if let Err(error) = publish {
                    let _cleanup_result = fs::remove_file(&destination);
                    let _cleanup_result = fs::remove_file(sidecar);
                    return Err(error);
                }
                self.prune()?;
                println!(
                    "Added {} {}: {}",
                    self.args.connection,
                    id,
                    item["Title"].as_str().ok_or("missing title")?
                );
                return Ok(());
            }
            state["cursor"] = Value::String(next);
            self.save(&state_path, &state)?;
            if inspections >= self.args.max_downloads {
                break;
            }
        }
        println!(
            "No new qualifying {} wallpaper; discovery progress saved.",
            self.args.connection
        );
        Ok(())
    }
}
async fn run() -> Result<()> {
    let deadline = Instant::now() + Duration::from_secs(240);
    let mut options = HashMap::new();
    let mut args = std::env::args_os().skip(1);
    while let Some(key) = args.next() {
        if options
            .insert(key, args.next().ok_or("missing option value")?)
            .is_some()
        {
            return Err("duplicate option".into());
        }
    }
    let path = |key: &str| -> Result<PathBuf> {
        options
            .get(std::ffi::OsStr::new(key))
            .map(PathBuf::from)
            .ok_or_else(|| format!("missing {key}").into())
    };
    let number = |key: &str, default: u64| -> Result<u64> {
        let value = options
            .get(std::ffi::OsStr::new(key))
            .map(|s| {
                s.to_str()
                    .ok_or("invalid numeric argument")
                    .and_then(|s| s.parse::<u64>().map_err(|_| "invalid numeric argument"))
            })
            .transpose()?
            .unwrap_or(default);
        if value == 0 {
            return Err("acquisition limits must be positive".into());
        }
        Ok(value)
    };
    if options.keys().any(|k| {
        !matches!(
            k.to_str(),
            Some(
                "--connection"
                    | "--plan"
                    | "--directory"
                    | "--state"
                    | "--width"
                    | "--height"
                    | "--max-images"
                    | "--max-pages"
                    | "--max-downloads"
            )
        )
    }) {
        return Err("unknown acquisition option".into());
    }
    let connection = options
        .get(std::ffi::OsStr::new("--connection"))
        .and_then(|s| s.to_str())
        .ok_or("connection required")?
        .to_owned();
    let provider = match connection.as_str() {
        "esaHubble" => Provider {
            host: "esahubble.org",
            prefix: "esa-hubble-",
        },
        "esaWebb" => Provider {
            host: "esawebb.org",
            prefix: "esa-webb-",
        },
        _ => return Err("unknown astronomy connection".into()),
    };
    let args = Args {
        connection,
        plan: path("--plan")?,
        directory: path("--directory")?,
        state: path("--state")?,
        width: number("--width", 3840)?,
        height: number("--height", 2160)?,
        max_images: usize::try_from(number("--max-images", 30)?)?,
        max_pages: usize::try_from(number("--max-pages", 3)?)?,
        max_downloads: usize::try_from(number("--max-downloads", 3)?)?,
    };
    let plan: Value = serde_json::from_slice(&fs::read(&args.plan)?)?;
    let routes = plan
        .as_array()
        .filter(|a| a.iter().all(Value::is_object))
        .ok_or("invalid wallpaper connection plan")?;
    let enabled: HashSet<String> = routes
        .iter()
        .filter(|r| r["connection"] == args.connection && r["category"] == "space")
        .filter_map(|r| r["subcategory"].as_str())
        .filter(|s| ["nebulae", "galaxies", "stars", "solar-system"].contains(s))
        .map(str::to_owned)
        .collect();
    if enabled.is_empty() {
        return Ok(());
    }
    for path in [&args.directory, &args.state] {
        fs::DirBuilder::new()
            .mode(0o700)
            .recursive(true)
            .create(path)?;
    }
    let lock = OpenOptions::new()
        .append(true)
        .create(true)
        .open(args.state.join(format!("{}fetch.lock", provider.prefix)))?;
    if let Err(error) = lock.try_lock_exclusive() {
        if error.kind() == std::io::ErrorKind::WouldBlock {
            return Ok(());
        }
        return Err(error.into());
    }
    let fetcher = Fetcher {
        deadline,
        provider,
        args,
        title: Regex::new(
            r"(?i)\b(artwork|artist.s (impression|concept)|illustration|simulation|diagram|chart|spectra|spectrum|annotated|comparison|collage|calendar|cover|poster|panels?|inset|infographic|compass|scale bar)\b",
        )?,
        description: Regex::new(
            r"(?i)\b(panels?|inset|labels?|labelled|labeled|annotated|scale bar|diagram|collage|illustration|artist.s (impression|concept))\b",
        )?,
        id: Regex::new(r"^[a-zA-Z0-9_-]+$")?,
        strip: Regex::new(r"<[^>]*>")?,
        visible: Regex::new(r"(?is)\[\s*Image Description\s*:(.*?)\]")?,
    };
    fetcher.discover(enabled).await
}
#[tokio::main(flavor = "current_thread")]
async fn main() -> std::process::ExitCode {
    match run().await {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("Astronomy wallpaper acquisition failed: {e}");
            std::process::ExitCode::FAILURE
        }
    }
}
