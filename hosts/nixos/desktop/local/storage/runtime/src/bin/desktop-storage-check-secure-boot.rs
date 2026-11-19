//! Check the firmware's SecureBoot EFI variable before hardware enrollment.
use std::{fs, path::Path};
fn enabled() -> std::io::Result<bool> {
    let mut values = Vec::new();
    for value in fs::read_dir(Path::new("/sys/firmware/efi/efivars"))? {
        let value = value?;
        if value
            .file_name()
            .to_string_lossy()
            .starts_with("SecureBoot-")
        {
            values.push(value.path());
        }
    }
    Ok(values.len() == 1 && fs::read(&values[0])?.get(4) == Some(&1))
}
fn main() {
    if !enabled().unwrap_or(false) {
        eprintln!("Firmware Secure Boot must be enabled before hardware enrollment.");
        std::process::exit(1);
    }
}
