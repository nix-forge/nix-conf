//! Seal the final Electron bundle with the reviewed upstream entitlement scopes.
use std::{
    error::Error,
    fs,
    path::{Path, PathBuf},
    process::{Command, ExitCode},
};
type Result<T> = std::result::Result<T, Box<dyn Error>>;
fn sign(bundle: &Path, upstream: &Path) -> Result<()> {
    let mut helpers = Vec::new();
    for entry in fs::read_dir(bundle.join("Contents/Frameworks"))? {
        let entry = entry?;
        if entry.path().extension().is_some_and(|s| s == "app") {
            helpers.push(entry.path());
        }
    }
    helpers.sort();
    let expected = [
        "Signal Helper (GPU).app",
        "Signal Helper (Plugin).app",
        "Signal Helper (Renderer).app",
        "Signal Helper.app",
    ];
    if helpers
        .iter()
        .map(|p| p.file_name().and_then(|s| s.to_str()))
        .collect::<Vec<_>>()
        != expected.map(Some)
    {
        return Err("Signal helper layout changed; review signing scopes".into());
    }
    let directory = tempfile::Builder::new()
        .prefix("signal-entitlements-")
        .tempdir()?;
    let mut plists = Vec::new();
    for name in ["entitlements.mac.plist", "entitlements.mac.inherit.plist"] {
        let raw = fs::read(upstream.join(name))?;
        let start = raw
            .windows(5)
            .position(|s| s == b"<?xml")
            .ok_or("Missing entitlement XML declaration")?;
        let mut entitlements = plist::Value::from_reader_xml(&raw[start..])?;
        entitlements
            .as_dictionary_mut()
            .ok_or("Entitlements must be a dictionary")?
            .insert(
                "com.apple.security.cs.disable-library-validation".into(),
                plist::Value::Boolean(true),
            );
        let destination = directory.path().join(name);
        entitlements.to_file_xml(&destination)?;
        plists.push(destination);
    }
    let mut command = Command::new("rcodesign");
    command
        .args([
            "sign",
            "--config-file",
            "/dev/null",
            "--code-signature-flags",
            "runtime",
            "--entitlements-xml-file",
        ])
        .arg(&plists[0]);
    for helper in helpers {
        let scope = helper
            .strip_prefix(bundle)?
            .to_str()
            .ok_or("Invalid helper path")?;
        command.args([
            "--code-signature-flags",
            &format!("{scope}:runtime"),
            "--entitlements-xml-file",
            &format!("{scope}:{}", plists[1].display()),
        ]);
    }
    if !command.arg(bundle).status()?.success() {
        return Err("Signal bundle signing failed".into());
    }
    Ok(())
}
fn main() -> ExitCode {
    let args: Vec<PathBuf> = std::env::args_os().skip(1).map(PathBuf::from).collect();
    let result = match args.as_slice() {
        [bundle, upstream] => sign(bundle, upstream),
        _ => Err("usage: sign-signal-bundle bundle upstream_build".into()),
    };
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("sign-signal-bundle: {error}");
            ExitCode::FAILURE
        }
    }
}
