//! Fingerprint only the user-visible fields managed by Dock reconciliation.
use plist::Value as Plist;
use serde_json::{Map, Value, json};
use sha2::{Digest, Sha256};
use std::{error::Error, io::Cursor, process::Command};
type Result<T> = std::result::Result<T, Box<dyn Error>>;
fn field<'a>(value: &'a Plist, name: &str) -> Option<&'a Plist> {
    value.as_dictionary().and_then(|d| d.get(name))
}
fn json_value(value: Option<&Plist>) -> Result<Value> {
    Ok(match value {
        None => Value::Null,
        Some(Plist::String(s)) => json!(s),
        Some(Plist::Boolean(v)) => json!(v),
        Some(Plist::Integer(v)) => {
            if let Some(n) = v.as_signed() {
                json!(n)
            } else {
                json!(v.as_unsigned().ok_or("Invalid plist integer")?)
            }
        }
        Some(Plist::Real(v)) if v.is_finite() => json!(v),
        Some(Plist::Array(a)) => Value::Array(
            a.iter()
                .map(|v| json_value(Some(v)))
                .collect::<Result<_>>()?,
        ),
        Some(Plist::Dictionary(d)) => Value::Object(
            d.iter()
                .map(|(k, v)| Ok((k.clone(), json_value(Some(v))?)))
                .collect::<Result<_>>()?,
        ),
        _ => return Err("Unsupported value in Dock layout".into()),
    })
}
fn tile(value: &Plist) -> Result<Value> {
    if value.as_dictionary().is_none() {
        return Ok(json!({"tile-type": "invalid"}));
    }
    let data = field(value, "tile-data");
    let mut result = Map::new();
    result.insert("tile-type".into(), json_value(field(value, "tile-type"))?);
    result.insert(
        "url".into(),
        json_value(
            data.and_then(|v| field(v, "file-data"))
                .and_then(|v| field(v, "_CFURLString")),
        )?,
    );
    for key in ["arrangement", "displayas", "showas"] {
        result.insert(key.into(), json_value(data.and_then(|v| field(v, key)))?);
    }
    Ok(Value::Object(result))
}
pub fn fingerprint() -> Result<String> {
    let binary = std::env::var_os("DOCK_DEFAULTS_BIN_OVERRIDE")
        .unwrap_or_else(|| "/usr/bin/defaults".into());
    let output = Command::new(binary)
        .args(["export", "com.apple.dock", "-"])
        .output()?;
    if !output.status.success() {
        return Err("Dock preference export failed".into());
    }
    let prefs = Plist::from_reader(Cursor::new(output.stdout))?;
    if prefs.as_dictionary().is_none() {
        return Err("The exported Dock preferences are not a dictionary".into());
    }
    let mut layout = Map::new();
    for section in ["persistent-apps", "persistent-others"] {
        let tiles = field(&prefs, section).and_then(Plist::as_array);
        let values = tiles
            .map(|tiles| tiles.iter().map(tile).collect::<Result<Vec<_>>>())
            .transpose()?
            .unwrap_or_default();
        layout.insert(section.into(), Value::Array(values));
    }
    // Python's previous public hash interface used sorted, compact, ASCII JSON.
    // Keep the exact Unicode escape spelling so existing receipts remain valid.
    let encoded = serde_json::to_string(&Value::Object(layout))?;
    let mut ascii = String::new();
    for ch in encoded.chars() {
        if ch.is_ascii() {
            ascii.push(ch);
        } else {
            for unit in ch.encode_utf16(&mut [0; 2]) {
                use std::fmt::Write;
                write!(ascii, "\\u{unit:04x}")?;
            }
        }
    }
    Ok(format!("{:x}", Sha256::digest(ascii.as_bytes())))
}
