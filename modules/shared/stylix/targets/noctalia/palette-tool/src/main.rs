//! Correct only Noctalia UI color roles; leave source surfaces/terminal colors intact.
use serde_json::{Map, Value};
use std::{error::Error, fs};
type Result<T> = std::result::Result<T, Box<dyn Error>>;

fn rgb(color: &str) -> Result<[f64; 3]> {
    let bytes = color.as_bytes();
    if bytes.len() != 7 || bytes[0] != b'#' || !bytes[1..].iter().all(u8::is_ascii_hexdigit) {
        return Err("expected an opaque #rrggbb palette color".into());
    }
    let channel = |offset| u8::from_str_radix(&color[offset..offset + 2], 16).map(f64::from);
    Ok([channel(1)?, channel(3)?, channel(5)?])
}
fn luminance(rgb: [f64; 3]) -> f64 {
    rgb.into_iter()
        .zip([0.2126, 0.7152, 0.0722])
        .map(|(byte, weight)| {
            let v = byte / 255.0;
            weight
                * if v <= 0.04045 {
                    v / 12.92
                } else {
                    ((v + 0.055) / 1.055).powf(2.4)
                }
        })
        .sum()
}
fn readable(foreground: &str, surfaces: &[String], endpoint: &str) -> Result<String> {
    let start = rgb(foreground)?;
    let end = rgb(endpoint)?;
    let surfaces = surfaces
        .iter()
        .map(|s| rgb(s).map(luminance))
        .collect::<Result<Vec<_>>>()?;
    for step in 0..256 {
        let color = std::array::from_fn(|i| {
            (start[i] + (end[i] - start[i]) * f64::from(step) / 255.0).round_ties_even()
        });
        let light = luminance(color);
        if surfaces
            .iter()
            .all(|s| (light.max(*s) + 0.05) / (light.min(*s) + 0.05) >= 4.75)
        {
            return Ok(format!(
                "#{:02x}{:02x}{:02x}",
                color[0] as u8, color[1] as u8, color[2] as u8
            ));
        }
    }
    Err("palette cannot meet the UI text contrast target with its foreground endpoints".into())
}
fn color(mode: &Map<String, Value>, role: &str) -> Result<String> {
    mode.get(role)
        .and_then(Value::as_str)
        .map(str::to_owned)
        .ok_or_else(|| format!("missing palette role: {role}").into())
}
fn correct(
    mode: &mut Map<String, Value>,
    role: &str,
    surfaces: &[String],
    endpoint: &str,
) -> Result<()> {
    let value = readable(&color(mode, role)?, surfaces, endpoint)?;
    mode.insert(role.into(), Value::String(value));
    Ok(())
}
fn run() -> Result<()> {
    let args: Vec<_> = std::env::args_os().skip(1).collect();
    let [source, destination] = args.as_slice() else {
        return Err("usage: noctalia-prepare-palette INPUT OUTPUT".into());
    };
    let mut palette: Value = serde_json::from_slice(&fs::read(source)?)?;
    let mode = palette
        .get_mut("dark")
        .and_then(Value::as_object_mut)
        .ok_or("palette dark mode must be an object")?;
    let surfaces = [color(mode, "mSurface")?, color(mode, "mSurfaceVariant")?];
    correct(mode, "mOnSurface", &surfaces, "#ffffff")?;
    let endpoint = color(mode, "mOnSurface")?;
    correct(mode, "mOnSurfaceVariant", &surfaces, &endpoint)?;
    for role in ["Primary", "Secondary", "Tertiary", "Error"] {
        let fill = format!("m{role}");
        correct(mode, &fill, &surfaces, &endpoint)?;
        let surface = color(mode, &fill)?;
        correct(mode, &format!("mOn{role}"), &[surface], "#000000")?;
    }
    mode.insert("mHover".into(), Value::String(color(mode, "mTertiary")?));
    mode.insert(
        "mOnHover".into(),
        Value::String(color(mode, "mOnTertiary")?),
    );
    let mut output = serde_json::to_vec_pretty(&palette)?;
    output.push(b'\n');
    fs::write(destination, output)?;
    Ok(())
}
fn main() -> std::process::ExitCode {
    match run() {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("noctalia-prepare-palette: {e}");
            std::process::ExitCode::FAILURE
        }
    }
}
