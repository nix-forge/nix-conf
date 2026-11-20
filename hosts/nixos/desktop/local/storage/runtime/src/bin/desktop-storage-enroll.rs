//! Explicit physical-console enrollment; never replaces a key or recovery slot.
use desktop_storage_runtime::{Result, read};
use serde_json::Value;
use std::{
    env,
    fs::{self, File, OpenOptions},
    io::{Read, Write},
    os::unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt},
    path::Path,
    process::{Command, ExitCode},
};
const ROOT: &str = "/dev/disk/by-partlabel/NIXOS-CRYPTROOT";
fn success(program: &str, args: &[&str]) -> Result<()> {
    if !Command::new(program).args(args).status()?.success() {
        return Err(format!("{program} did not complete successfully").into());
    }
    Ok(())
}
fn capture(program: &str, args: &[&str]) -> Result<Vec<u8>> {
    let output = Command::new(program).args(args).output()?;
    if !output.status.success() {
        return Err(format!("{program} did not complete successfully").into());
    }
    Ok(output.stdout)
}
fn luks(device: &str) -> Result<()> {
    success("cryptsetup", &["isLuks", "--type", "luks2", device])
}
fn protected_directory(path: &Path) -> Result<()> {
    fs::create_dir_all(path)?;
    fs::set_permissions(path, fs::Permissions::from_mode(0o700))?;
    Ok(())
}
fn key(device: &str, path: &str) -> Result<()> {
    luks(device)?;
    let path = Path::new(path);
    protected_directory(path.parent().ok_or("keyfile has no parent")?)?;
    match OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(path)
    {
        Ok(mut file) => {
            let mut data = [0; 64];
            File::open("/dev/urandom")?.read_exact(&mut data)?;
            file.write_all(&data)?;
            file.sync_all()?;
        }
        Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => (),
        Err(e) => return Err(e.into()),
    }
    let file = OpenOptions::new()
        .read(true)
        .custom_flags(rustix::fs::OFlags::NOFOLLOW.bits() as i32)
        .open(path)?;
    let metadata = file.metadata()?;
    if !metadata.is_file()
        || metadata.uid() != 0
        || metadata.mode() & 0o7777 != 0o600
        || metadata.nlink() != 1
    {
        return Err("key must be a root-owned single-link regular file with mode 0600".into());
    }
    let path = path.to_str().ok_or("keyfile path is not UTF-8")?;
    if Command::new("cryptsetup")
        .args(["open", "--test-passphrase", "--key-file", path, device])
        .status()?
        .success()
    {
        println!("The existing key is already enrolled.");
    } else {
        println!("Enter the existing volume recovery passphrase when cryptsetup asks.");
        success("cryptsetup", &["luksAddKey", device, path])?;
        success(
            "cryptsetup",
            &["open", "--test-passphrase", "--key-file", path, device],
        )?;
    }
    Ok(())
}
fn tokens() -> Result<Value> {
    Ok(serde_json::from_slice(&capture(
        "cryptsetup",
        &["luksDump", "--dump-json-metadata", ROOT],
    )?)?)
}
fn has_token(value: &Value, require_pin: bool) -> bool {
    value["tokens"].as_object().is_some_and(|tokens| {
        tokens.values().any(|token| {
            token["type"] == "systemd-tpm2" && (!require_pin || token["tpm2-pin"] == true)
        })
    })
}
fn string<'a>(policy: &'a Value, field: &str) -> Result<&'a str> {
    policy[field]
        .as_str()
        .ok_or_else(|| format!("missing enrollment policy {field}").into())
}
fn run() -> Result<()> {
    let args: Vec<_> = env::args().skip(1).collect();
    if !(1..=2).contains(&args.len()) {
        return Err(
            "usage: desktop-storage-enroll POLICY {data-key|homelab-key|tpm-pin|fido2|headers}"
                .into(),
        );
    }
    if !rustix::process::geteuid().is_root() {
        return Err("Run this command as root at the physical console.".into());
    }
    rustix::process::umask(rustix::fs::Mode::from_raw_mode(0o077));
    luks(ROOT)?;
    if !capture("findmnt", &["-n", "-o", "SOURCE", "/"])?.starts_with(b"/dev/mapper/cryptroot") {
        return Err("Boot the installed encrypted root before enrollment.".into());
    }
    let policy = read(&args[0])?;
    match args.get(1).map(String::as_str).unwrap_or("help") {
        "data-key" => key(
            "/dev/disk/by-partlabel/NIXOS-CRYPTDATA",
            string(&policy, "dataKeyFile")?,
        )?,
        "homelab-key" => key(
            "/dev/disk/by-partlabel/HOMELAB-CRYPT",
            string(&policy, "homelabKeyFile")?,
        )?,
        "tpm-pin" => {
            success(string(&policy, "secureBootCheck")?, &[])?;
            if policy["measuredBoot"] != true {
                return Err("Boot a generation with managed measured boot enabled first.".into());
            }
            let pcr_path = string(&policy, "pcrlockPolicy")?;
            let pcr = read(pcr_path)?;
            if pcr["pcrValues"]
                .as_array()
                .map(|a| a.iter().map(|v| v["pcr"].clone()).collect::<Vec<_>>())
                != Some(vec![Value::from(4)])
            {
                return Err(
                    "The managed policy must cover PCR 4 only; PCR 7 is bound directly.".into(),
                );
            }
            success(string(&policy, "pcrlockExecutable")?, &["is-supported"])?;
            if has_token(&tokens()?, false) {
                return Err("A TPM token already exists. Review it and use the documented recovery procedure before replacing it.".into());
            }
            println!("First test the recovery passphrase. This does not alter its slot.");
            success("cryptsetup", &["open", "--test-passphrase", ROOT])?;
            success(
                "systemd-cryptenroll",
                &[
                    "--tpm2-device=auto",
                    "--tpm2-with-pin=yes",
                    "--tpm2-pcrs=7",
                    &format!("--tpm2-pcrlock={pcr_path}"),
                    ROOT,
                ],
            )?;
            if !has_token(&tokens()?, true) {
                return Err("Enrollment did not produce a TPM token with PIN protection.".into());
            }
        }
        "fido2" => {
            success(string(&policy, "secureBootCheck")?, &[])?;
            println!(
                "Connect exactly one intended YubiKey. Repeat for the second key after testing the first."
            );
            success("cryptsetup", &["open", "--test-passphrase", ROOT])?;
            success(
                "systemd-cryptenroll",
                &[
                    "--fido2-device=auto",
                    "--fido2-with-client-pin=yes",
                    "--fido2-with-user-presence=yes",
                    ROOT,
                ],
            )?;
        }
        "headers" => {
            let root = Path::new("/var/lib/desktop-storage/recovery");
            protected_directory(root)?;
            let destination = tempfile::Builder::new()
                .prefix("headers.")
                .tempdir_in(root)?
                .keep();
            for (device, name) in [
                (ROOT, "root"),
                ("/dev/disk/by-partlabel/NIXOS-CRYPTDATA", "data"),
                ("/dev/disk/by-partlabel/HOMELAB-CRYPT", "homelab"),
            ] {
                if name == "homelab" && luks(device).is_err() {
                    continue;
                }
                success(
                    "cryptsetup",
                    &[
                        "luksHeaderBackup",
                        device,
                        "--header-backup-file",
                        destination
                            .join(format!("{name}.header"))
                            .to_str()
                            .ok_or("backup path is not UTF-8")?,
                    ],
                )?;
            }
            println!(
                "Header backups created in the protected recovery directory. Copy them to independent encrypted storage."
            );
        }
        _ => {
            println!(
                "Usage: desktop-storage-enroll {{data-key|homelab-key|tpm-pin|fido2|headers}}"
            );
            println!(
                "No command formats drives, resets a key, removes recovery slots, or changes firmware."
            );
        }
    }
    Ok(())
}
fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("desktop-storage-enroll: {error}");
            ExitCode::FAILURE
        }
    }
}
