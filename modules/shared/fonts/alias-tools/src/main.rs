use serde_json::Value;
use std::{collections::BTreeSet, error::Error, fs, path::Path, process::Command};
type Result<T> = std::result::Result<T, Box<dyn Error>>;
fn scan(path: &Path, families: &mut BTreeSet<String>) -> Result<()> {
    for entry in fs::read_dir(path)? {
        let entry = entry?;
        // Match find -type f: never follow symlinked files or directories.
        let kind = entry.file_type()?;
        if kind.is_dir() {
            scan(&entry.path(), families)?;
        } else if kind.is_file() {
            let out = Command::new("fc-scan")
                .arg("--format=%{family[0]}\n")
                .arg(entry.path())
                .output()?;
            // fc-scan can produce useful families before rejecting a face.
            families.extend(
                String::from_utf8(out.stdout)?
                    .split_terminator('\n')
                    .filter(|s| !s.is_empty())
                    .map(str::to_owned),
            );
        }
    }
    Ok(())
}
fn xml(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&apos;")
}
fn run() -> Result<()> {
    let args: Vec<_> = std::env::args_os().skip(1).collect();
    if args.len() != 2 {
        return Err("usage: fontconfig-alias-tools POLICY OUTPUT".into());
    }
    let policy: Value = serde_json::from_slice(&fs::read(&args[0])?)?;
    let string = |key: &str| -> Result<&str> {
        policy[key]
            .as_str()
            .ok_or_else(|| format!("missing {key}").into())
    };
    let fallback = string("privateUseFallbackFamily")?;
    let exact = [
        fallback,
        string("blinkMacSystemFamily")?,
        string("appleColorEmojiFamily")?,
        string("appleHelveticaNeueFamily")?,
        "sans-serif",
        "serif",
        "monospace",
        "cursive",
        "fantasy",
        "emoji",
        "math",
        "fangsong",
        "system",
        "system-ui",
        "ui-serif",
        "ui-sans-serif",
        "ui-monospace",
        "ui-rounded",
        "ui",
    ];
    let prefixes = [
        string("appleSystemFamily")?,
        string("appleSansPrefix")?,
        string("appleSerifPrefix")?,
    ];
    let mut families = BTreeSet::new();
    for directory in policy["fontDirectories"]
        .as_array()
        .ok_or("missing directories")?
    {
        let path = Path::new(directory.as_str().ok_or("invalid directory")?);
        if fs::symlink_metadata(path).is_ok_and(|m| m.is_dir()) {
            scan(path, &mut families)?;
        }
    }
    let mut output = String::from(
        "<?xml version=\"1.0\"?>\n<!DOCTYPE fontconfig SYSTEM \"urn:fontconfig:fonts.dtd\">\n<fontconfig>\n",
    );
    for family in families {
        if exact.contains(&family.as_str()) || prefixes.iter().any(|p| family.starts_with(p)) {
            continue;
        }
        output.push_str(&format!("  <match target=\"pattern\">\n    <test qual=\"first\" name=\"family\" compare=\"eq\">\n      <string>{}</string>\n    </test>\n    <edit name=\"family\" mode=\"append\" binding=\"weak\">\n      <string>{}</string>\n    </edit>\n  </match>\n", xml(&family), xml(fallback)));
    }
    output.push_str("</fontconfig>\n");
    fs::write(&args[1], output)?;
    Ok(())
}
fn main() -> std::process::ExitCode {
    match run() {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("font aliases: {e}");
            std::process::ExitCode::FAILURE
        }
    }
}
