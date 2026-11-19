use fs2::FileExt;
use serde_json::Value;
use std::{
    collections::HashSet,
    env,
    fs::{self, OpenOptions},
    io::Write,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
};
type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
fn escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\r', "&#13;")
}
fn uri(path: &str) -> String {
    let mut out = String::from("file://");
    for b in path.bytes() {
        if b.is_ascii_alphanumeric() || b"/_.-~".contains(&b) {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}
fn identity(s: &str) -> String {
    let Some((scheme, tail)) = s.split_once(':') else {
        return s.into();
    };
    if !scheme.eq_ignore_ascii_case("file") {
        return s.into();
    }
    let tail = tail.split(['?', '#']).next().unwrap_or("");
    let path = if let Some(rest) = tail.strip_prefix("//") {
        let (host, path) = rest.split_once('/').unwrap_or((rest, ""));
        if !host.is_empty() && host != "localhost" {
            return s.into();
        }
        format!("/{path}")
    } else {
        tail.into()
    };
    let mut decoded = Vec::new();
    let bytes = path.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%'
            && i + 2 < bytes.len()
            && let Ok(n) = std::str::from_utf8(&bytes[i + 1..i + 3])
                .ok()
                .and_then(|s| u8::from_str_radix(s, 16).ok())
                .ok_or(())
        {
            decoded.push(n);
            i += 3;
            continue;
        }
        decoded.push(bytes[i]);
        i += 1;
    }
    let decoded = String::from_utf8_lossy(&decoded);
    let absolute = decoded.starts_with('/');
    let double = decoded.starts_with("//") && !decoded.starts_with("///");
    let mut parts = Vec::new();
    for p in decoded.split('/') {
        match p {
            "" | "." => {}
            ".." => {
                if parts.last().is_some_and(|p| *p != "..") {
                    parts.pop();
                } else if !absolute {
                    parts.push(p);
                }
            }
            p => parts.push(p),
        }
    }
    let result = format!(
        "{}{}",
        if double {
            "//"
        } else if absolute {
            "/"
        } else {
            ""
        },
        parts.join("/")
    );
    format!("file:{}", if result.is_empty() { "." } else { &result })
}
fn read(path: &Path) -> Result<Vec<u8>> {
    if fs::symlink_metadata(path).is_ok_and(|m| m.file_type().is_symlink()) {
        return Err(format!(
            "{} is a symlink; migrate it to a writable file before syncing",
            path.display()
        )
        .into());
    }
    match fs::read(path) {
        Ok(b) => Ok(b),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(vec![]),
        Err(e) => Err(e.into()),
    }
}
fn gtk(original: &[u8], entries: &[(String, String)]) -> Result<Vec<u8>> {
    let text = std::str::from_utf8(original)?;
    let mut existing = text
        .lines()
        .filter(|s| !s.trim().is_empty())
        .map(|s| identity(s.split(' ').next().unwrap_or("")))
        .collect::<HashSet<_>>();
    let mut out = original.to_vec();
    for (uri, label) in entries {
        if existing.insert(identity(uri)) {
            if !out.is_empty() && !out.ends_with(b"\n") {
                out.push(b'\n');
            }
            out.extend_from_slice(format!("{uri} {label}\n").as_bytes());
        }
    }
    Ok(out)
}
// XML readers accept UTF-8, UTF-16 and ISO-8859-1 byte streams. Rewrites use
// UTF-8, while callers keep the original bytes when no managed value changes.
fn xml_text(bytes: &[u8]) -> Result<String> {
    let little = bytes.starts_with(&[0xff, 0xfe]) || bytes.starts_with(&[b'<', 0]);
    let big = bytes.starts_with(&[0xfe, 0xff]) || bytes.starts_with(&[0, b'<']);
    let mut text = if little || big {
        let skip =
            usize::from(bytes.starts_with(&[0xff, 0xfe]) || bytes.starts_with(&[0xfe, 0xff])) * 2;
        let bytes = &bytes[skip..];
        if !bytes.len().is_multiple_of(2) {
            return Err("truncated UTF-16 XML".into());
        }
        let units = bytes
            .as_chunks::<2>()
            .0
            .iter()
            .map(|pair| {
                if little {
                    u16::from_le_bytes([pair[0], pair[1]])
                } else {
                    u16::from_be_bytes([pair[0], pair[1]])
                }
            })
            .collect::<Vec<_>>();
        String::from_utf16(&units)?
    } else {
        let head = String::from_utf8_lossy(&bytes[..bytes.len().min(256)]);
        let encoding = xml_encoding(&head).map(|r| head[r].to_ascii_lowercase());
        match encoding.as_deref() {
            Some("iso-8859-1" | "iso_8859-1" | "latin-1" | "latin1") => {
                bytes.iter().map(|b| char::from(*b)).collect()
            }
            _ => std::str::from_utf8(bytes)?
                .trim_start_matches('\u{feff}')
                .to_owned(),
        }
    };
    if let Some(range) = xml_encoding(&text) {
        text.replace_range(range, "UTF-8");
    }
    Ok(text)
}
fn xml_encoding(text: &str) -> Option<std::ops::Range<usize>> {
    if !text.starts_with("<?xml") {
        return None;
    }
    let end = text.find("?>")?;
    let start = text[..end].find("encoding")? + "encoding".len();
    let tail = &text[start..end];
    let equals = tail.find('=')?;
    let rest = tail[equals + 1..].trim_start();
    let quote = rest.chars().next()?;
    if quote != '\'' && quote != '"' {
        return None;
    }
    let offset = start + equals + 1 + (tail[equals + 1..].len() - rest.len()) + 1;
    Some(offset..offset + text[offset..end].find(quote)?)
}
fn kde(original: &[u8], entries: &[(String, String)]) -> Result<Vec<u8>> {
    let text = if original.is_empty() {
        "<xbel version=\"1.0\"/>".to_owned()
    } else {
        xml_text(original)?
    };
    let doc = roxmltree::Document::parse(&text)?;
    let root = doc.root_element();
    if root.tag_name().name() != "xbel"
        || text[root.range().start + 1..]
            .split([' ', '\t', '\r', '\n', '/', '>'])
            .next()
            != Some("xbel")
    {
        return Err("KDE Places must have an xbel root".into());
    }
    let mut existing = root
        .descendants()
        .filter(|n| {
            n.is_element()
                && n.tag_name().name() == "bookmark"
                && text[n.range().start + 1..]
                    .split([' ', '\t', '\r', '\n', '/', '>'])
                    .next()
                    == Some("bookmark")
        })
        .map(|n| identity(n.attribute("href").unwrap_or("")))
        .collect::<HashSet<_>>();
    let mut additions = String::new();
    for (uri, label) in entries {
        if existing.insert(identity(uri)) {
            additions.push_str(&format!(
                "<bookmark href=\"{}\"><title>{}</title></bookmark>",
                escape(uri),
                escape(label)
            ));
        }
    }
    if additions.is_empty() {
        return Ok(original.to_vec());
    }
    let range = root.range();
    let source = &text[range.clone()];
    let mut out = text.to_owned();
    if source.ends_with("/>") {
        out.replace_range(range.end - 2..range.end, &format!(">{additions}</xbel>"));
    } else {
        let index = range.start + source.rfind("</").ok_or("missing closing tag")?;
        out.insert_str(index, &additions);
    }
    Ok(out.into_bytes())
}
fn write(path: &Path, content: &[u8]) -> Result<()> {
    let parent = path.parent().ok_or("no parent")?;
    fs::create_dir_all(parent)?;
    let mode = fs::metadata(path)
        .map(|m| m.permissions().mode() & 0o777)
        .unwrap_or(0o600);
    let mut tmp = tempfile::NamedTempFile::new_in(parent)?;
    tmp.as_file()
        .set_permissions(fs::Permissions::from_mode(mode))?;
    tmp.write_all(content)?;
    tmp.flush()?;
    tmp.as_file().sync_all()?;
    tmp.persist(path)?;
    Ok(())
}
fn run() -> Result<()> {
    let args = env::args().skip(1).collect::<Vec<_>>();
    let arg = |key: &str| -> Result<PathBuf> {
        args.windows(2)
            .find(|p| p[0] == key)
            .map(|p| PathBuf::from(&p[1]))
            .ok_or_else(|| format!("missing {key}").into())
    };
    let home = arg("--home").or_else(|_| {
        env::var("HOME")
            .map(PathBuf::from)
            .map_err(Box::<dyn std::error::Error>::from)
    })?;
    let config = arg("--config-home")?;
    let data = arg("--data-home")?;
    let dry = args.iter().any(|s| s == "--dry-run");
    let policy: Value = serde_json::from_slice(&fs::read(arg("--config")?)?)?;
    let mut entries = Vec::new();
    for entry in policy.as_array().ok_or("entries must be an array")? {
        let path = entry["path"].as_str().ok_or("invalid path")?;
        let label = entry["label"].as_str().ok_or("invalid label")?;
        if !Path::new(path).is_absolute() || label.contains(['\r', '\n', '\0']) {
            return Err("Bookmark paths must be absolute and labels must be single lines".into());
        }
        if Path::new(path).is_dir() {
            entries.push((uri(path), label.to_owned()));
        }
    }
    let _lock = if dry {
        None
    } else {
        fs::create_dir_all(&config)?;
        let lock = OpenOptions::new()
            .append(true)
            .create(true)
            .open(config.join(".directory-bookmarks.lock"))?;
        FileExt::lock_exclusive(&lock)?;
        Some(lock)
    };
    let legacy = home.join(".gtk-bookmarks");
    let legacy_content = read(&legacy)?;
    let modern = config.join("gtk-3.0/bookmarks");
    let mut targets = vec![
        (modern.clone(), false),
        (data.join("user-places.xbel"), true),
    ];
    if legacy.exists() {
        targets.push((legacy, false));
    }
    let mut updates = Vec::new();
    for (path, xml) in targets {
        let original = read(&path)?;
        let seed = if path == modern && !path.exists() {
            &legacy_content
        } else {
            &original
        };
        let content = if xml {
            kde(seed, &entries)?
        } else {
            gtk(seed, &entries)?
        };
        if content != original {
            updates.push((path, content));
        }
    }
    if !dry {
        for (path, content) in updates {
            write(&path, &content)?;
        }
    }
    Ok(())
}
fn main() {
    if let Err(e) = run() {
        eprintln!("{e}");
        std::process::exit(1);
    }
}
