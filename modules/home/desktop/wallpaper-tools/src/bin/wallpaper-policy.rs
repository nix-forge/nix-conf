//! Shared mutable wallpaper policy; cached provenance is rechecked each rotation.
use fs2::FileExt;
use regex::{Regex, RegexBuilder};
use serde_json::{Map, Value, json};
use std::{
    collections::{BTreeSet, HashMap, HashSet},
    error::Error,
    ffi::OsString,
    fs::{self, OpenOptions},
    io::{BufRead, Write},
    os::unix::{ffi::OsStringExt, fs::DirBuilderExt},
    path::{Path, PathBuf},
};
type Result<T> = std::result::Result<T, Box<dyn Error>>;
fn object(v: &Value) -> Result<&Map<String, Value>> {
    v.as_object().ok_or_else(|| "expected a JSON object".into())
}
fn read(path: &Path) -> Result<Value> {
    let value = serde_json::from_slice(&fs::read(path)?)?;
    object(&value)?;
    Ok(value)
}
fn blank() -> Value {
    json!({})
}
fn switches(value: &Value, names: &Value, nullable: bool) -> Result<()> {
    let names = object(names)?;
    if object(value)?.iter().any(|(name, value)| {
        !names.contains_key(name) || !(value.is_boolean() || (nullable && value.is_null()))
    }) {
        return Err("unknown wallpaper switch or invalid switch type".into());
    }
    Ok(())
}
fn node(value: &Value, catalog: &Value, leaves: &Value) -> Result<()> {
    if object(value)?
        .keys()
        .any(|k| !["enable", "connections", "subcategories"].contains(&k.as_str()))
    {
        return Err("invalid wallpaper category settings".into());
    }
    if value.get("enable").is_some_and(|v| !v.is_boolean()) {
        return Err("category enable must be true or false".into());
    }
    switches(
        value.get("connections").unwrap_or(&blank()),
        &catalog["connections"],
        true,
    )?;
    let empty = blank();
    let children = value.get("subcategories").unwrap_or(&empty);
    for (name, child) in object(children)? {
        if !object(leaves)?.contains_key(name) {
            return Err("unknown wallpaper subcategory".into());
        }
        node(child, catalog, &blank())?;
    }
    Ok(())
}
fn validate(settings: &Value, catalog: &Value) -> Result<()> {
    if object(settings)?
        .keys()
        .any(|k| !["connections", "categories", "personal"].contains(&k.as_str()))
    {
        return Err("unknown wallpaper settings".into());
    }
    switches(
        settings.get("connections").unwrap_or(&blank()),
        &catalog["connections"],
        false,
    )?;
    if settings.get("personal").is_some_and(|v| !v.is_boolean()) {
        return Err("personal wallpaper switch must be true or false".into());
    }
    let empty = blank();
    for (name, value) in object(settings.get("categories").unwrap_or(&empty))? {
        let category = catalog["categories"]
            .get(name)
            .ok_or("unknown wallpaper category")?;
        node(value, catalog, &category["subcategories"])?;
    }
    Ok(())
}
fn merge(base: &Value, overrides: &Value) -> Value {
    match (base.as_object(), overrides.as_object()) {
        (Some(base), Some(overrides)) => {
            let mut result = base.clone();
            for (k, v) in overrides {
                let current = result
                    .get(k)
                    .map(|old| merge(old, v))
                    .unwrap_or_else(|| v.clone());
                result.insert(k.clone(), current);
            }
            Value::Object(result)
        }
        _ => overrides.clone(),
    }
}
fn allowed(settings: &Value, connection: &str, category: &str, subcategory: &str) -> bool {
    if settings["connections"][connection].as_bool() != Some(true) {
        return false;
    }
    let parent = &settings["categories"][category];
    let child = &parent["subcategories"][subcategory];
    if parent.get("enable").and_then(Value::as_bool) == Some(false)
        || child.get("enable").and_then(Value::as_bool) == Some(false)
    {
        return false;
    }
    for scope in [child, parent] {
        if let Some(value) = scope["connections"][connection].as_bool() {
            return value;
        }
    }
    true
}
fn plan(settings: &Value, catalog: &Value, connection: Option<&str>) -> Result<Vec<Value>> {
    let mut result = Vec::new();
    for route in catalog["routes"]
        .as_array()
        .ok_or("invalid wallpaper catalog routes")?
    {
        let conn = route["connection"]
            .as_str()
            .ok_or("invalid route connection")?;
        let category = route["category"].as_str().ok_or("invalid route category")?;
        let sub = route["subcategory"]
            .as_str()
            .ok_or("invalid route subcategory")?;
        if connection.is_none_or(|c| c == conn) && allowed(settings, conn, category, sub) {
            result.push(route.clone());
        }
    }
    Ok(result)
}
struct Engine<'a> {
    settings: &'a Value,
    catalog: &'a Value,
    supported: HashMap<String, HashSet<String>>,
    rejected_subjects: Option<Regex>,
    rejected_categories: Option<Regex>,
}
impl<'a> Engine<'a> {
    fn new(settings: &'a Value, catalog: &'a Value) -> Result<Self> {
        let mut supported: HashMap<String, HashSet<String>> = HashMap::new();
        for route in plan(settings, catalog, None)? {
            supported
                .entry(route["connection"].as_str().ok_or("invalid route")?.into())
                .or_default()
                .insert(format!(
                    "{}/{}",
                    route["category"].as_str().ok_or("invalid route")?,
                    route["subcategory"].as_str().ok_or("invalid route")?
                ));
        }
        let regex = |name| -> Result<Option<Regex>> {
            catalog["commonsQuality"]
                .get(name)
                .map(|v| {
                    Ok(
                        RegexBuilder::new(v.as_str().ok_or("invalid rejection expression")?)
                            .case_insensitive(true)
                            .build()?,
                    )
                })
                .transpose()
        };
        Ok(Self {
            settings,
            catalog,
            supported,
            rejected_subjects: regex("rejectedSubjects")?,
            rejected_categories: regex("rejectedCategories")?,
        })
    }
    fn assignments(&self, metadata: &Value, connection: &str) -> Result<BTreeSet<String>> {
        let Some(categories) = metadata["metadata"]["Categories"]["value"].as_str() else {
            return Ok(BTreeSet::new());
        };
        let subject = [
            metadata["title"].as_str(),
            metadata["metadata"]["ImageDescription"]["value"].as_str(),
            Some(categories),
        ]
        .into_iter()
        .flatten()
        .collect::<Vec<_>>()
        .join(" ");
        let normalized = categories.replace('_', " ");
        let collections: HashSet<_> = normalized.split('|').collect();
        if self
            .rejected_subjects
            .as_ref()
            .is_some_and(|r| r.is_match(&subject))
            || self
                .rejected_categories
                .as_ref()
                .is_some_and(|r| collections.iter().any(|c| r.is_match(c)))
        {
            return Ok(BTreeSet::new());
        }
        let mut groups = BTreeSet::new();
        for route in self.catalog["routes"].as_array().ok_or("invalid catalog")? {
            let member = |key: &str, excluded: bool| -> Result<bool> {
                Ok(route
                    .get(key)
                    .map(|v| v.as_array().ok_or("invalid collections"))
                    .transpose()?
                    .is_none_or(|items| {
                        if excluded {
                            items
                                .iter()
                                .all(|v| v.as_str().is_some_and(|s| !collections.contains(s)))
                        } else {
                            items
                                .iter()
                                .all(|v| v.as_str().is_some_and(|s| collections.contains(s)))
                        }
                    }))
            };
            if route["connection"] == connection
                && route["collection"]
                    .as_str()
                    .is_some_and(|c| collections.contains(c))
                && member("requireCollections", false)?
                && member("excludeCollections", true)?
            {
                groups.insert(format!(
                    "{}/{}",
                    route["category"].as_str().ok_or("invalid route")?,
                    route["subcategory"].as_str().ok_or("invalid route")?
                ));
            }
        }
        Ok(groups)
    }
    fn eligible(&self, path: &Path) -> bool {
        self.check(path).unwrap_or(false)
    }
    fn check(&self, path: &Path) -> Result<bool> {
        let name = path.file_name().unwrap_or_default().to_string_lossy();
        if ["nasa-svs-", "nasa-image-library-", "cma-", "smithsonian-"]
            .iter()
            .any(|s| name.starts_with(s))
        {
            return Ok(false);
        }
        let inferred = [
            ("wikimedia-commons-", "wikimediaCommons"),
            ("esa-hubble-", "esaHubble"),
            ("esa-webb-", "esaWebb"),
        ]
        .into_iter()
        .find(|(prefix, _)| name.starts_with(prefix))
        .map(|(_, source)| source);
        let personal = inferred.is_none()
            && self
                .settings
                .get("personal")
                .and_then(Value::as_bool)
                .unwrap_or(true);
        let mut sidecar = path.as_os_str().to_os_string();
        sidecar.push(".json");
        let sidecar = PathBuf::from(sidecar);
        if !sidecar.exists() {
            return Ok(personal);
        }
        let metadata = read(&sidecar)?;
        let connection = match metadata.get("connection") {
            Some(Value::String(value)) => Some(value.as_str()),
            Some(Value::Null) => return Ok(personal),
            Some(_) => return Ok(false),
            None => inferred,
        };
        let Some(connection) = connection else {
            return Ok(personal);
        };
        if !object(&self.catalog["connections"])?.contains_key(connection)
            || inferred.is_some_and(|i| i != connection)
        {
            return Ok(false);
        }
        let groups = if connection == "wikimediaCommons" {
            self.assignments(&metadata, connection)?
        } else {
            metadata
                .get("wallpaper_categories")
                .map(|v| v.as_array().ok_or("invalid wallpaper categories"))
                .transpose()?
                .into_iter()
                .flatten()
                .filter_map(Value::as_str)
                .map(str::to_owned)
                .collect()
        };
        Ok(self
            .supported
            .get(connection)
            .is_some_and(|supported| groups.iter().any(|g| supported.contains(g))))
    }
}
fn entry<'a>(target: &'a mut Value, key: &str) -> Result<&'a mut Value> {
    Ok(target
        .as_object_mut()
        .ok_or("invalid wallpaper settings shape")?
        .entry(key)
        .or_insert_with(blank))
}
fn change(overrides: &mut Value, args: &[String], catalog: &Value) -> Result<()> {
    let command = args.first().ok_or("command required")?.as_str();
    let expected = match command {
        "personal" => 2,
        "source" => 4,
        _ => 3,
    };
    if args.len() != expected {
        return Err("incorrect wallpaper command arguments".into());
    }
    let setting = args.last().ok_or("setting required")?;
    if !["on", "off", "default"].contains(&setting.as_str())
        && !(command == "source" && setting == "inherit")
    {
        return Err("invalid wallpaper switch value".into());
    }
    let mut node = overrides;
    let key = match command {
        "connection" => {
            if catalog["connections"].get(&args[1]).is_none() {
                return Err("unknown connection".into());
            }
            node = entry(node, "connections")?;
            args[1].as_str()
        }
        "personal" => "personal",
        "source" | "category" => {
            let target = &args[if command == "source" { 2 } else { 1 }];
            let parts: Vec<_> = target.split('/').collect();
            let category = catalog["categories"]
                .get(parts[0])
                .ok_or("unknown category")?;
            if parts.len() > 2
                || (parts.len() == 2 && category["subcategories"].get(parts[1]).is_none())
            {
                return Err("unknown subcategory".into());
            }
            node = entry(entry(node, "categories")?, parts[0])?;
            if parts.len() == 2 {
                node = entry(entry(node, "subcategories")?, parts[1])?;
            }
            if command == "source" {
                if catalog["connections"].get(&args[1]).is_none() {
                    return Err("unknown connection".into());
                }
                node = entry(node, "connections")?;
                args[1].as_str()
            } else {
                "enable"
            }
        }
        _ => return Err("invalid wallpaper mutation".into()),
    };
    let node = node.as_object_mut().ok_or("invalid wallpaper settings")?;
    if setting == "default" {
        node.remove(key);
    } else {
        node.insert(
            key.into(),
            if setting == "inherit" {
                Value::Null
            } else {
                Value::Bool(setting == "on")
            },
        );
    }
    Ok(())
}
fn run() -> Result<i32> {
    let mut options = HashMap::new();
    let mut rest = Vec::new();
    let mut args = std::env::args_os().skip(1);
    while let Some(arg) = args.next() {
        if matches!(
            arg.to_str(),
            Some("--catalog" | "--config" | "--preferences")
        ) {
            if options
                .insert(arg, args.next().ok_or("missing option value")?)
                .is_some()
            {
                return Err("duplicate wallpaper option".into());
            }
        } else {
            rest.push(arg);
        }
    }
    let required = |key: &str| -> Result<PathBuf> {
        options
            .get(std::ffi::OsStr::new(key))
            .map(PathBuf::from)
            .ok_or_else(|| format!("missing {key}").into())
    };
    let catalog = read(&required("--catalog")?)?;
    let defaults = read(&required("--config")?)?;
    let preferences = required("--preferences")?;
    validate(&defaults, &catalog)?;
    let command = rest
        .first()
        .and_then(|s| s.to_str())
        .ok_or("wallpaper command required")?;
    if ["connection", "category", "source", "personal"].contains(&command) {
        let parent = preferences
            .parent()
            .filter(|p| !p.as_os_str().is_empty())
            .unwrap_or(Path::new("."));
        fs::DirBuilder::new()
            .recursive(true)
            .mode(0o700)
            .create(parent)?;
        let lock = OpenOptions::new()
            .create(true)
            .truncate(true)
            .write(true)
            .open(preferences.with_extension("lock"))?;
        lock.lock_exclusive()?;
        let mut overrides = if preferences.exists() {
            read(&preferences)?
        } else {
            blank()
        };
        validate(&overrides, &catalog)?;
        let mutation = rest
            .iter()
            .map(|s| {
                s.to_str()
                    .map(str::to_owned)
                    .ok_or("wallpaper names must be UTF-8")
            })
            .collect::<std::result::Result<Vec<_>, _>>()?;
        change(&mut overrides, &mutation, &catalog)?;
        validate(&overrides, &catalog)?;
        let mut file = tempfile::NamedTempFile::new_in(parent)?;
        serde_json::to_writer_pretty(&mut file, &overrides)?;
        writeln!(file)?;
        file.as_file().sync_all()?;
        file.persist(&preferences)?;
    }
    let overrides = if preferences.exists() {
        read(&preferences)?
    } else {
        blank()
    };
    validate(&overrides, &catalog)?;
    let settings = merge(&defaults, &overrides);
    match command {
        "eligible" if rest.len() == 2 => {
            return Ok(
                if Engine::new(&settings, &catalog)?.eligible(Path::new(&rest[1])) {
                    0
                } else {
                    1
                },
            );
        }
        "filter" if rest.len() == 2 && rest[1] == "--null" => {
            let engine = Engine::new(&settings, &catalog)?;
            let input = std::io::stdin();
            let mut input = input.lock();
            let output = std::io::stdout();
            let mut output = output.lock();
            let mut record = Vec::new();
            loop {
                record.clear();
                if input.read_until(0, &mut record)? == 0 {
                    break;
                }
                if record.last() == Some(&0) {
                    record.pop();
                }
                if !record.is_empty()
                    && engine.eligible(Path::new(&OsString::from_vec(record.clone())))
                {
                    output.write_all(&record)?;
                    output.write_all(&[0])?;
                }
            }
        }
        "plan" if rest.len() <= 2 => {
            let connection = rest
                .get(1)
                .map(|s| s.to_str().ok_or("invalid connection"))
                .transpose()?;
            if connection.is_some_and(|s| catalog["connections"].get(s).is_none()) {
                return Err("unknown connection".into());
            }
            println!(
                "{}",
                serde_json::to_string(&plan(&settings, &catalog, connection)?)?
            );
        }
        "status" | "connection" | "category" | "source" | "personal" => println!(
            "{}",
            serde_json::to_string_pretty(
                &json!({"settings":settings,"active_routes":plan(&settings,&catalog,None)?,"catalog":catalog})
            )?
        ),
        _ => return Err("invalid wallpaper command arguments".into()),
    }
    Ok(0)
}
fn main() {
    match run() {
        Ok(code) => std::process::exit(code),
        Err(e) => {
            eprintln!("Wallpaper preferences: {e}");
            std::process::exit(65);
        }
    }
}
