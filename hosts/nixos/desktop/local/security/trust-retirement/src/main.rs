//! Retire the exact root-owned preview only after declarative trust owns aliases.
use std::{
    error::Error,
    fs,
    os::unix::fs::MetadataExt,
    path::{Path, PathBuf},
};
type Result<T> = std::result::Result<T, Box<dyn Error>>;
fn owned_link(path: &Path, target: &Path) -> Result<bool> {
    let info = match fs::symlink_metadata(path) {
        Ok(info) => info,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(false),
        Err(e) => return Err(e.into()),
    };
    Ok(info.file_type().is_symlink() && info.uid() == 0 && fs::read_link(path)? == target)
}
fn exists(path: &Path) -> Result<bool> {
    match fs::symlink_metadata(path) {
        Ok(_) => Ok(true),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(e) => Err(e.into()),
    }
}
fn run() -> Result<()> {
    if !rustix::process::geteuid().is_root() {
        return Err("trust preview retirement requires root".into());
    }
    let args: Vec<_> = std::env::args_os().skip(1).collect();
    let [bundle, trust_source] = args.as_slice() else {
        return Err("bundle and trust source required".into());
    };
    let bundle = Path::new(bundle).canonicalize()?;
    let trust_source = Path::new(trust_source).canonicalize()?;
    for (name, target) in [
        ("/etc/ssl/certs/ca-certificates.crt", &bundle),
        ("/etc/ssl/certs/ca-bundle.crt", &bundle),
        ("/etc/pki/tls/certs/ca-bundle.crt", &bundle),
        ("/etc/ssl/trust-source", &trust_source),
    ] {
        let path = Path::new(name);
        let alias = PathBuf::from(format!("/etc/static{}", &name[4..]));
        if !owned_link(path, &alias)? || path.canonicalize()? != *target {
            return Ok(());
        }
    }
    let unit = Path::new("/usr/local/lib/systemd/system/desktop-ca-preview.service");
    let root = Path::new("/nix/var/nix/gcroots/desktop-trust-preview-20261021");
    let package = match fs::read_link(root) {
        Ok(path) => path,
        Err(_) => return Ok(()),
    };
    if package.parent() != Some(Path::new("/nix/store"))
        || !package
            .file_name()
            .is_some_and(|s| s.to_string_lossy().ends_with("-desktop-trust-preview"))
        || !owned_link(root, &package)?
    {
        return Ok(());
    }
    let source = package.join("desktop-ca-preview.service");
    let wanted =
        Path::new("/usr/local/lib/systemd/system/sysinit.target.wants/desktop-ca-preview.service");
    // Validate all existing entries before removing any; keep the GC root last so
    // interrupted cleanup can be resumed without deleting foreign replacements.
    if (exists(unit)? && !owned_link(unit, &source)?)
        || (exists(wanted)? && !owned_link(wanted, unit)?)
    {
        return Ok(());
    }
    if exists(wanted)? {
        fs::remove_file(wanted)?;
    }
    if exists(unit)? {
        fs::remove_file(unit)?;
    }
    fs::remove_file(root)?;
    Ok(())
}
fn main() -> std::process::ExitCode {
    match run() {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(_) => {
            eprintln!("Unable to safely retire the boot trust preview");
            std::process::ExitCode::FAILURE
        }
    }
}
