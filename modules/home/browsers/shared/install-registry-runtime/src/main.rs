use std::{env, fs, io::Write, os::unix::fs::PermissionsExt, path::Path};
fn run() -> Result<String, Box<dyn std::error::Error>> {
    let args = env::args().skip(1).collect::<Vec<_>>();
    if args.len() != 6 {
        return Err(
            "expected --profiles-registry FILE --install-registry FILE --default-profile PATH"
                .into(),
        );
    }
    let arg = |flag| -> Result<&str, Box<dyn std::error::Error>> {
        args.as_chunks::<2>()
            .0
            .iter()
            .find(|p| p[0] == flag)
            .map(|p| p[1].as_str())
            .ok_or_else(|| format!("missing {flag}").into())
    };
    let profiles = arg("--profiles-registry")?;
    let path = Path::new(arg("--install-registry")?);
    let default = arg("--default-profile")?;
    if !default.starts_with("Profiles/")
        || default.contains(['\n', '\r'])
        || default.split('/').any(|s| s == "..")
    {
        return Err("invalid relative profile path".into());
    }
    if !fs::read_to_string(profiles)?
        .lines()
        .any(|line| line.strip_prefix("Path=") == Some(default))
    {
        return Err("default profile is absent from profiles registry".into());
    }
    let meta = match fs::symlink_metadata(path) {
        Ok(m) => m,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            return Ok("install registry does not exist yet".into());
        }
        Err(e) => return Err(e.into()),
    };
    if !meta.is_file() {
        return Err("install registry is not a regular file".into());
    }
    let content = fs::read_to_string(path)?;
    let mut count = 0;
    let updated = content
        .split_inclusive('\n')
        .map(|line| {
            let (body, ending) = if let Some(s) = line.strip_suffix("\r\n") {
                (s, "\r\n")
            } else if let Some(s) = line.strip_suffix('\n') {
                (s, "\n")
            } else {
                (line, "")
            };
            if body.starts_with("Default=") && body.strip_prefix("Default=") != Some(default) {
                count += 1;
                format!("Default={default}{ending}")
            } else {
                line.to_owned()
            }
        })
        .collect::<String>();
    if count == 0 {
        return Ok("install registry is already current".into());
    }
    let mut tmp = tempfile::NamedTempFile::new_in(path.parent().ok_or("no parent")?)?;
    tmp.write_all(updated.as_bytes())?;
    tmp.flush()?;
    tmp.as_file().sync_all()?;
    tmp.as_file().set_permissions(fs::Permissions::from_mode(
        meta.permissions().mode() & 0o7777,
    ))?;
    tmp.persist(path)?;
    Ok(format!("reconciled {count} stale install mappings"))
}
fn main() {
    match run() {
        Ok(s) => println!("{s}"),
        Err(e) => {
            eprintln!("error: {e}");
            std::process::exit(1);
        }
    }
}
