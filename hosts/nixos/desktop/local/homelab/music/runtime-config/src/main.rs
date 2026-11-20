//! Materialize private Soularr INI only inside its service runtime directory.
use std::{error::Error, fs, io::Write, path::PathBuf};
fn run() -> Result<(), Box<dyn Error>> {
    let args: Vec<_> = std::env::args_os().skip(1).collect();
    let [settings] = args.as_slice() else {
        return Err("settings template required".into());
    };
    let credentials = PathBuf::from(
        std::env::var_os("CREDENTIALS_DIRECTORY").ok_or("credentials directory missing")?,
    );
    let runtime =
        PathBuf::from(std::env::var_os("RUNTIME_DIRECTORY").ok_or("runtime directory missing")?);
    let key = fs::read_to_string(credentials.join("lidarr-api-key"))?
        .trim()
        .to_owned();
    let mut slskd_key = None;
    for line in fs::read_to_string(credentials.join("slskd-settings"))?.lines() {
        if let Some((name, value)) = line.split_once('=')
            && name.trim() == "SLSKD_API_KEY"
        {
            let values = shell_words::split(value)?;
            if let [value] = values.as_slice() {
                slskd_key = Some(value.clone());
            }
        }
    }
    let slskd_key = slskd_key
        .filter(|s| !s.is_empty())
        .ok_or("missing music integration credential")?;
    if key.is_empty()
        || key
            .chars()
            .chain(slskd_key.chars())
            .any(|c| "\r\n$%".contains(c))
    {
        return Err("invalid music integration credential".into());
    }
    let text = fs::read_to_string(settings)?
        .replace("@LIDARR_KEY@", &key)
        .replace("@SLSKD_KEY@", &slskd_key);
    let mut target = tempfile::NamedTempFile::new_in(&runtime)?;
    target.write_all(text.as_bytes())?;
    target.as_file().sync_all()?;
    target.persist(runtime.join("config.ini"))?;
    Ok(())
}
fn main() -> std::process::ExitCode {
    match run() {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(_) => {
            eprintln!("Unable to materialize private music configuration");
            std::process::ExitCode::FAILURE
        }
    }
}
