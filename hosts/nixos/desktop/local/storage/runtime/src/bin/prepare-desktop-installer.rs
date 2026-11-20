use desktop_storage_runtime::*;
use serde_json::json;
use std::{
    fs,
    io::Write,
    os::unix::fs::{DirBuilderExt, OpenOptionsExt},
};
fn disk(value: &str) -> Result<()> {
    if !regex::Regex::new(r"^/dev/disk/by-id/[A-Za-z0-9._+:-]+$")?.is_match(value)
        || [".", ".."].contains(&value.rsplit('/').next().unwrap_or(""))
        || regex::Regex::new(r"-part\d+$")?.is_match(value)
    {
        return usage("Use a whole-drive /dev/disk/by-id path");
    }
    Ok(())
}
fn main() {
    entry(|| {
        let a = args();
        let system =
            option(&a, "--system-disk").ok_or_else(|| usage_error("--system-disk required"))?;
        let data = option(&a, "--data-disk").ok_or_else(|| usage_error("--data-disk required"))?;
        disk(&system)?;
        disk(&data)?;
        if system == data {
            return usage("System and data disks must differ");
        }
        let source = fs::canonicalize(
            option(&a, "--source").ok_or_else(|| usage_error("--source required"))?,
        )?;
        for file in ["flake.nix", "flake.lock", "nix-seal/flake.nix"] {
            if !source.join(file).is_file() {
                return usage("Source must be complete checkout including nix-seal");
            }
        }
        let git = cmd(&[
            "git",
            "-C",
            &source.to_string_lossy(),
            "rev-parse",
            "--show-toplevel",
        ])?;
        if fs::canonicalize(git.trim())? != source {
            return usage("Source must be Git checkout root");
        }
        cmd(&[
            "git",
            "-C",
            &source.to_string_lossy(),
            "ls-files",
            "--error-unmatch",
            "flake.nix",
            "flake.lock",
            "hosts/shared/local/flake/desktop-installer.nix",
            "hosts/nixos/desktop/local/storage/.storage-roles.nix",
            "hosts/nixos/desktop/local/storage/disk-layout.nix",
            "hosts/nixos/desktop/local/storage/deployment.nix",
        ])?;
        let output = std::path::absolute(
            option(&a, "--output").ok_or_else(|| usage_error("--output required"))?,
        )?;
        let mut normalized = std::path::PathBuf::new();
        for part in output.components() {
            match part {
                std::path::Component::ParentDir => {
                    normalized.pop();
                }
                std::path::Component::CurDir => {}
                v => normalized.push(v.as_os_str()),
            }
        }
        let output = normalized;
        if output.starts_with(&source) {
            return usage("Output must be outside source checkout");
        }
        if let Some(parent) = output.parent() {
            fs::create_dir_all(parent)?;
            if fs::canonicalize(parent)?.starts_with(&source) {
                return usage("Output resolves inside source checkout");
            }
        }
        fs::DirBuilder::new().mode(0o700).create(&output)?;
        let uri = source
            .to_string_lossy()
            .bytes()
            .map(|b| {
                if b.is_ascii_alphanumeric() || b"/-._~".contains(&b) {
                    (b as char).to_string()
                } else {
                    format!("%{b:02X}")
                }
            })
            .collect::<String>();
        let rendered = include_str!("../../assets/desktop-installer-flake.nix.in")
            .replace(
                "BASE_URL",
                &json!(format!("git+file://{uri}?submodules=1")).to_string(),
            )
            .replace("SYSTEM_DISK", &json!(system).to_string())
            .replace("DATA_DISK", &json!(data).to_string());
        let target = output.join("flake.nix");
        fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&target)?
            .write_all(rendered.as_bytes())?;
        println!(
            "{}\nNo disk has been inspected or modified. Verify both paths on the installer before running Disko.",
            target.display()
        );
        Ok(0)
    })
}
