//! Preserve application-owned settings while reconciling Nix-owned preferences.
use serde_json::{Map, Value};
use std::error::Error;
use std::fs;
use std::io::{self, Write};
use std::path::{Component, Path, PathBuf};

type Result<T> = std::result::Result<T, Box<dyn Error>>;

fn object<'a>(value: &'a mut Value, name: &str) -> Result<&'a mut Map<String, Value>> {
    value
        .as_object_mut()
        .ok_or_else(|| format!("{name} must be an object").into())
}

fn configure(data_dir: &Path, preferences: &Path, model: &Path, model_name: &Path) -> Result<()> {
    if !matches!(
        model_name.components().collect::<Vec<_>>().as_slice(),
        [Component::Normal(_)]
    ) {
        return Err("model name must be a single filename".into());
    }
    let preferences: Value = serde_json::from_slice(&fs::read(preferences)?)?;
    let preferences = preferences
        .as_object()
        .ok_or("preferences must be an object")?;
    fs::create_dir_all(data_dir)?;
    let target = data_dir.join("settings_store.json");
    let mut document: Value = match fs::read(&target) {
        Ok(bytes) => serde_json::from_slice(&bytes)?,
        Err(error) if error.kind() == io::ErrorKind::NotFound => Value::Object(Map::new()),
        Err(error) => return Err(error.into()),
    };
    let settings = object(&mut document, "Handy document")?
        .entry("settings")
        .or_insert_with(|| Value::Object(Map::new()));
    let settings = object(settings, "Handy settings")?;
    for (key, value) in preferences {
        if key != "bindings" {
            settings.insert(key.clone(), value.clone());
        }
    }
    if let Some(bindings) = preferences.get("bindings") {
        let bindings = bindings
            .as_object()
            .ok_or("bindings policy must be an object")?;
        let target = settings
            .entry("bindings")
            .or_insert_with(|| Value::Object(Map::new()));
        let target = object(target, "Handy bindings")?;
        for (key, binding) in bindings {
            let binding = binding
                .as_object()
                .ok_or("binding policy must be an object")?;
            let current = target
                .entry(key.clone())
                .or_insert_with(|| Value::Object(Map::new()));
            object(current, "Handy binding")?.extend(binding.clone());
        }
    }
    let models = data_dir.join("models");
    fs::create_dir_all(&models)?;
    let link = models.join(model_name);
    match fs::symlink_metadata(&link) {
        Ok(metadata) if metadata.file_type().is_symlink() => {
            // Nix supplies an absolute store path. Compare the link itself so a
            // dangling old store link is replaced as well.
            if fs::read_link(&link)? != model {
                fs::remove_file(&link)?;
                std::os::unix::fs::symlink(model, &link)?;
            }
        }
        Ok(_) => {} // A downloaded model belongs to the user.
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            std::os::unix::fs::symlink(model, &link)?
        }
        Err(error) => return Err(error.into()),
    }
    // Same-directory rename is atomic; a failed parse never replaces settings.
    // NamedTempFile owns cleanup on every error path and creates mode 0600.
    let mut temporary = tempfile::NamedTempFile::new_in(data_dir)?;
    serde_json::to_writer_pretty(&mut temporary, &document)?;
    writeln!(temporary)?;
    temporary.as_file().sync_all()?;
    temporary.persist(&target)?;
    fs::File::open(data_dir)?.sync_all()?;
    Ok(())
}

fn run() -> Result<()> {
    let mut args = std::env::args_os().skip(1);
    let mut options = std::collections::BTreeMap::new();
    while let Some(key) = args.next() {
        if !["--data-dir", "--preferences", "--model", "--model-name"]
            .iter()
            .any(|name| key == *name)
        {
            return Err(format!("unknown argument: {}", key.to_string_lossy()).into());
        }
        let value = args.next().ok_or("missing option value")?;
        if options.insert(key, PathBuf::from(value)).is_some() {
            return Err("duplicate option".into());
        }
    }
    let required = |name: &str| {
        options
            .get(std::ffi::OsStr::new(name))
            .map(PathBuf::as_path)
            .ok_or_else(|| format!("missing {name}"))
    };
    configure(
        required("--data-dir")?,
        required("--preferences")?,
        required("--model")?,
        required("--model-name")?,
    )
}

fn main() -> std::process::ExitCode {
    match run() {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("configure-voice-dictation: {error}");
            std::process::ExitCode::FAILURE
        }
    }
}
