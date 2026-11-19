use serde_json::Value;
use std::{
    env, fs,
    io::Write,
    os::unix::fs::{DirBuilderExt, PermissionsExt},
    path::Path,
};
type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
const OOR: &str = "http://openoffice.org/2001/registry";
fn escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\r', "&#13;")
}
fn attribute(s: &str) -> String {
    escape(s).replace('\n', "&#10;").replace('\t', "&#9;")
}
fn opening_end(source: &str) -> Result<usize> {
    let mut quote = None;
    for (i, c) in source.char_indices() {
        if let Some(q) = quote {
            if c == q {
                quote = None;
            }
        } else if c == '\'' || c == '"' {
            quote = Some(c);
        } else if c == '>' {
            return Ok(i + 1);
        }
    }
    Err("invalid opening tag".into())
}
fn append(text: &str, node: roxmltree::Node<'_, '_>, addition: &str) -> Result<String> {
    let range = node.range();
    let source = &text[range.clone()];
    let mut out = text.to_owned();
    if source.ends_with("/>") {
        let name = source[1..]
            .split([' ', '\t', '\r', '\n', '/', '>'])
            .next()
            .ok_or("missing name")?;
        out.replace_range(range.end - 2..range.end, &format!(">{addition}</{name}>"));
    } else {
        let index = range.start + source.rfind("</").ok_or("missing closing tag")?;
        out.insert_str(index, addition);
    }
    Ok(out)
}
fn apply(text: &str, setting: &Value) -> Result<String> {
    let doc = roxmltree::Document::parse(text)?;
    let root = doc.root_element();
    let path = setting["path"].as_str().ok_or("invalid setting path")?;
    let name = setting["name"].as_str().ok_or("invalid setting name")?;
    let desired = setting["value"].as_str().ok_or("invalid setting value")?;
    let matches = root
        .children()
        .filter(|n| n.has_tag_name("item") && n.attribute((OOR, "path")) == Some(path))
        .flat_map(|n| n.children())
        .filter(|n| n.has_tag_name("prop") && n.attribute((OOR, "name")) == Some(name))
        .collect::<Vec<_>>();
    let Some(first) = matches.first() else {
        return append(
            text,
            root,
            &format!(
                "<item xmlns=\"\" xmlns:oor=\"{OOR}\" oor:path=\"{}\"><prop oor:name=\"{}\" oor:op=\"fuse\"><value>{}</value></prop></item>",
                attribute(path),
                attribute(name),
                escape(desired)
            ),
        );
    };
    let mut edits = Vec::new();
    if let Some(value) = first.children().find(|n| n.has_tag_name("value")) {
        if value.text() != Some(desired) {
            let r = value.range();
            let source = &text[r.clone()];
            if source.ends_with("/>") {
                let updated = append(text, value, &escape(desired))?;
                let growth = updated.len() - text.len();
                edits.push((r.clone(), updated[r.start..r.end + growth].into()));
            } else {
                let start = r.start + opening_end(source)?;
                let end = value
                    .children()
                    .find(|n| !n.is_text())
                    .map(|n| n.range().start)
                    .unwrap_or(r.start + source.rfind("</").ok_or("invalid value")?);
                edits.push((start..end, escape(desired)));
            }
        }
    } else {
        let updated = append(text, *first, &format!("<value>{}</value>", escape(desired)))?;
        let r = first.range();
        let growth = updated.len() - text.len();
        edits.push((r.clone(), updated[r.start..r.end + growth].into()));
    }
    let duplicate_ids = matches.iter().skip(1).map(|n| n.id()).collect::<Vec<_>>();
    let mut removed_parents = Vec::new();
    for duplicate in matches.iter().skip(1) {
        let parent = duplicate.parent().ok_or("missing item")?;
        if parent
            .children()
            .filter(|n| n.is_element())
            .all(|n| duplicate_ids.contains(&n.id()))
        {
            if !removed_parents.contains(&parent.id()) {
                edits.push((parent.range(), String::new()));
                removed_parents.push(parent.id());
            }
        } else {
            edits.push((duplicate.range(), String::new()));
        }
    }
    edits.sort_by_key(|e| std::cmp::Reverse(e.0.start));
    let mut out = text.to_owned();
    for (r, s) in edits {
        out.replace_range(r, &s);
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
fn run() -> Result<()> {
    let args = env::args().skip(1).collect::<Vec<_>>();
    if args.len() != 2 {
        return Err("usage: libreoffice-settings PROFILE SETTINGS".into());
    }
    let profile = Path::new(&args[0]);
    let parent = profile.parent().ok_or("missing parent")?;
    fs::DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(parent)?;
    let original = match fs::read(profile) {
        Ok(bytes) => match xml_text(&bytes) {
            Ok(s) => s,
            Err(e) => {
                eprintln!(
                    "warning: LibreOffice profile is malformed; settings were not changed: {e}"
                );
                return Ok(());
            }
        },
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => format!(
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?><oor:items xmlns:oor=\"{OOR}\" xmlns:xs=\"http://www.w3.org/2001/XMLSchema\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"/>"
        ),
        Err(e) => return Err(e.into()),
    };
    match roxmltree::Document::parse(&original) {
        Ok(doc) if doc.root_element().has_tag_name((OOR, "items")) => {}
        _ => {
            eprintln!(
                "warning: LibreOffice profile is malformed or has an unexpected root element; settings were not changed"
            );
            return Ok(());
        }
    }
    let settings: Value = serde_json::from_slice(&fs::read(&args[1])?)?;
    let mut updated = original.clone();
    for setting in settings.as_array().ok_or("settings must be an array")? {
        updated = apply(&updated, setting)?;
    }
    if updated == original {
        return Ok(());
    }
    if profile.exists() {
        let backup = profile.with_file_name(format!(
            "{}.home-manager-backup",
            profile.file_name().ok_or("missing name")?.to_string_lossy()
        ));
        fs::copy(profile, &backup)?;
        let meta = fs::metadata(profile)?;
        fs::File::options().write(true).open(backup)?.set_times(
            fs::FileTimes::new()
                .set_accessed(meta.accessed()?)
                .set_modified(meta.modified()?),
        )?;
    }
    let mut tmp = tempfile::Builder::new()
        .prefix(".registrymodifications.")
        .suffix(".xcu")
        .tempfile_in(parent)?;
    tmp.write_all(updated.as_bytes())?;
    tmp.as_file()
        .set_permissions(fs::Permissions::from_mode(0o600))?;
    tmp.persist(profile)?;
    Ok(())
}
fn main() {
    if let Err(e) = run() {
        eprintln!("{e}");
        std::process::exit(1);
    }
}
