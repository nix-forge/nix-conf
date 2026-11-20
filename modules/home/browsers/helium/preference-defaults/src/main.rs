use nix_conf_legacy_numbers::python_float;
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::{env, fs, io::Write, path::Path};
type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;

// Python json.dumps(sort_keys=True) uses ASCII escapes and spaced separators.
// Keep this wire representation stable: existing profiles carry its SHA256.
fn canonical(value: &Value) -> Result<String> {
    Ok(match value {
        Value::String(s) => {
            let mut out = String::from("\"");
            for c in s.chars() {
                match c {
                    '"' => out.push_str("\\\""),
                    '\\' => out.push_str("\\\\"),
                    '\n' => out.push_str("\\n"),
                    '\r' => out.push_str("\\r"),
                    '\t' => out.push_str("\\t"),
                    '\u{8}' => out.push_str("\\b"),
                    '\u{c}' => out.push_str("\\f"),
                    c if !(' '..='~').contains(&c) => {
                        for unit in c.encode_utf16(&mut [0; 2]) {
                            out.push_str(&format!("\\u{unit:04x}"));
                        }
                    }
                    c => out.push(c),
                }
            }
            out.push('"');
            out
        }
        Value::Array(a) => format!(
            "[{}]",
            a.iter()
                .map(canonical)
                .collect::<Result<Vec<_>>>()?
                .join(", ")
        ),
        Value::Object(m) => {
            let mut entries = m.iter().collect::<Vec<_>>();
            entries.sort_by(|a, b| a.0.cmp(b.0));
            format!(
                "{{{}}}",
                entries
                    .into_iter()
                    .map(|(k, v)| Ok(format!(
                        "{}: {}",
                        canonical(&Value::String(k.clone()))?,
                        canonical(v)?
                    )))
                    .collect::<Result<Vec<_>>>()?
                    .join(", ")
            )
        }
        Value::Number(n) => {
            let raw = n.to_string();
            if raw.contains(['.', 'e', 'E']) {
                python_float(raw.parse()?)?
            } else if raw == "-0" {
                "0".into()
            } else {
                raw
            }
        }
        _ => value.to_string(),
    })
}
fn merge(target: &mut Value, source: &Value) -> Result<()> {
    let source = source.as_object().ok_or("defaults must be an object")?;
    if !target.is_object() {
        *target = serde_json::json!({});
    }
    let target = target
        .as_object_mut()
        .ok_or("preferences must be an object")?;
    for (key, value) in source {
        if value.is_object() {
            merge(target.entry(key).or_insert(Value::Null), value)?;
        } else {
            target.insert(key.clone(), value.clone());
        }
    }
    Ok(())
}
fn run() -> Result<()> {
    let args = env::args().skip(1).collect::<Vec<_>>();
    if args.len() != 2 {
        return Err("usage: helium-preference-defaults POLICY PREFERENCES".into());
    }
    let policy: Value = serde_json::from_slice(&fs::read(&args[0])?)?;
    let revision = format!(
        "{}",
        base16ct::HexDisplay(&Sha256::digest(canonical(&policy)?.as_bytes()))
    );
    let path = Path::new(&args[1]);
    let mut prefs: Value = match fs::read(path) {
        Ok(bytes) => serde_json::from_slice(&bytes).unwrap_or_else(|_| serde_json::json!({})),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => serde_json::json!({}),
        Err(e) => return Err(e.into()),
    };
    if !prefs.is_object() {
        return Err("preferences must be an object".into());
    }
    if let Some(helium) = prefs.get("helium")
        && !helium.is_object()
    {
        return Err("helium preferences must be an object".into());
    }
    if prefs
        .pointer("/helium/nix_default_preferences_hash")
        .and_then(Value::as_str)
        == Some(&revision)
    {
        return Ok(());
    }
    merge(&mut prefs, &policy["values"])?;
    for keys in policy["remove"]
        .as_array()
        .ok_or("remove must be an array")?
    {
        let keys = keys.as_array().ok_or("removal must be an array")?;
        let (last, parents) = keys.split_last().ok_or("empty removal path")?;
        let mut parent = Some(&mut prefs);
        for key in parents {
            parent = parent.and_then(|p| p.get_mut(key.as_str()?));
        }
        if let Some(object) = parent.and_then(Value::as_object_mut) {
            object.remove(last.as_str().ok_or("invalid removal key")?);
        }
    }
    if prefs.get("helium").is_none() {
        prefs["helium"] = serde_json::json!({});
    }
    let helium = prefs["helium"]
        .as_object_mut()
        .ok_or("helium must be an object")?;
    helium.insert(
        "nix_default_preferences_hash".into(),
        Value::String(revision),
    );
    let dir = path.parent().ok_or("missing parent")?;
    fs::create_dir_all(dir)?;
    let mut tmp = tempfile::Builder::new()
        .prefix("Preferences.nix-")
        .tempfile_in(dir)?;
    serde_json::to_writer(&mut tmp, &prefs)?;
    tmp.flush()?;
    tmp.as_file().sync_all()?;
    tmp.persist(path)?;
    Ok(())
}
fn main() {
    if let Err(e) = run() {
        eprintln!("{e}");
        std::process::exit(1);
    }
}
