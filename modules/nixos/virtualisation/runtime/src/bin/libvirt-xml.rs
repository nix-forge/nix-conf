//! Bounded XML operations for managed libvirt objects.
use roxmltree::{Document, Node};
use std::{
    env,
    fs::File,
    io::{self, Read},
};
type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
fn child<'a, 'input>(root: Node<'a, 'input>, name: &str) -> Result<Option<Node<'a, 'input>>> {
    let mut matches = root
        .children()
        .filter(|e| e.has_tag_name(name) && e.tag_name().namespace().is_none());
    let first = matches.next();
    if matches.next().is_some() {
        return Err(format!("duplicate {name} element").into());
    }
    Ok(first)
}
fn node_text(node: Node<'_, '_>) -> String {
    node.children()
        .take_while(|n| !n.is_element())
        .filter(|n| n.is_text())
        .filter_map(|n| n.text())
        .collect()
}
fn text(root: Node<'_, '_>, name: &str) -> Result<String> {
    Ok(child(root, name)?.map(node_text).unwrap_or_default())
}

fn attr(root: Node<'_, '_>, name: &str, key: &str) -> Result<String> {
    Ok(child(root, name)?
        .and_then(|e| e.attribute(key))
        .unwrap_or("")
        .to_owned())
}
struct Disk {
    device: String,
    source: String,
    target: String,
    bus: String,
    serial: String,
    readonly: bool,
}
fn disks(root: Node<'_, '_>) -> Result<Vec<Disk>> {
    let devices = child(root, "devices")?.ok_or("domain has no devices")?;
    let mut disks = Vec::new();
    let mut targets = std::collections::HashSet::new();
    for node in devices
        .children()
        .filter(|e| e.has_tag_name("disk") && e.tag_name().namespace().is_none())
    {
        let disk = Disk {
            device: node.attribute("device").unwrap_or("").into(),
            source: attr(node, "source", "file")?,
            target: attr(node, "target", "dev")?,
            bus: attr(node, "target", "bus")?,
            serial: text(node, "serial")?,
            readonly: child(node, "readonly")?.is_some(),
        };
        if disk.target.is_empty() || !targets.insert(disk.target.clone()) {
            return Err("disk targets must be present and unique".into());
        }
        disks.push(disk);
    }
    Ok(disks)
}
fn read(mut reader: impl Read) -> Result<String> {
    let mut bytes = Vec::new();
    reader
        .by_ref()
        .take(4 * 1024 * 1024 + 1)
        .read_to_end(&mut bytes)?;
    if bytes.len() > 4 * 1024 * 1024 {
        return Err("libvirt XML exceeds the size limit".into());
    }
    let text = String::from_utf8(bytes)?;
    for tail in text.split("<!").skip(1) {
        let declaration = tail.trim_start().to_ascii_uppercase();
        if declaration.starts_with("DOCTYPE") || declaration.starts_with("ENTITY") {
            return Err("libvirt XML must not contain DTD or entity declarations".into());
        }
    }
    Ok(text)
}
fn run() -> Result<String> {
    let args: Vec<String> = env::args().skip(1).collect();
    let command = args.first().map(String::as_str).unwrap_or("");
    let (source, kind) = match (command, args.len()) {
        ("preserve-uuid", 5) if ["network", "pool"].contains(&args[1].as_str()) => {
            (read(File::open(&args[4])?)?, args[1].as_str())
        }
        ("installer-topology", 5) => (read(File::open(&args[1])?)?, "domain"),
        ("disk-source", 2) => (read(io::stdin().lock())?, "domain"),
        ("pool-path", 1) => (read(io::stdin().lock())?, "pool"),
        _ => return Err("invalid command arguments".into()),
    };
    let source = source.trim_start_matches('\u{feff}');
    let document = Document::parse(source)?;
    let root = document.root_element();
    if !root.has_tag_name(kind) || root.tag_name().namespace().is_some() {
        return Err(format!("expected a {kind} document").into());
    }
    match command {
        "preserve-uuid" => {
            if text(root, "name")? != args[2] {
                return Err("definition names a different libvirt object".into());
            }
            let value = &args[3];
            if value.len() != 36
                || !value.bytes().enumerate().all(|(i, b)| {
                    if [8, 13, 18, 23].contains(&i) {
                        b == b'-'
                    } else {
                        b.is_ascii_hexdigit()
                    }
                })
            {
                return Err("existing object returned an invalid UUID".into());
            }
            let expected = uuid::Uuid::parse_str(value)?;
            let replacement = format!("<uuid>{expected}</uuid>");
            let mut output = source.to_owned();
            if let Some(existing) = child(root, "uuid")? {
                if uuid::Uuid::parse_str(&node_text(existing))? != expected {
                    return Err("refusing to replace an existing object's UUID".into());
                }
                // A matching UUID already establishes identity; retain its
                // complete representation and any unrelated attributes.
            } else {
                // Use parser-provided byte ranges, retaining every unrelated
                // namespace, attribute, comment, and whitespace byte.
                let end = root.range().end;
                let closing = source[..end]
                    .rfind("</")
                    .ok_or("missing object closing tag")?;
                output.insert_str(closing, &replacement);
            }
            Ok(output)
        }
        "pool-path" => {
            let target = child(root, "target")?.ok_or("pool has no target path")?;
            let path = text(target, "path")?;
            if path.is_empty() {
                return Err("pool has no target path".into());
            }
            Ok(path)
        }
        "disk-source" => {
            for disk in disks(root)? {
                if disk.device == "disk" && disk.target == args[1] {
                    if disk.source.is_empty() {
                        return Err("managed system disk must have a file source".into());
                    }
                    return Ok(disk.source);
                }
            }
            Ok(String::new())
        }
        "installer-topology" => {
            let disks = disks(root)?;
            let writable: Vec<_> = disks
                .iter()
                .filter(|d| d.device == "disk" && !d.readonly)
                .collect();
            let helpers: Vec<_> = disks
                .iter()
                .filter(|d| d.device == "disk" && d.readonly)
                .collect();
            let optical: Vec<_> = disks.iter().filter(|d| d.device == "cdrom").collect();
            if writable.len() != 1 {
                return Err("installer must expose exactly one writable disk".into());
            }
            let disk = writable[0];
            if disk.source != args[2]
                || disk.serial != args[3]
                || disk.target != "sda"
                || disk.bus != "sata"
            {
                return Err("installer writable disk does not match the managed SATA disk".into());
            }
            if helpers.len() != 1 || helpers[0].source != args[4] {
                return Err("installer must expose the read-only driver-prime disk".into());
            }
            if optical.len() != 3 || optical.iter().any(|d| !d.readonly) {
                return Err("installer must expose exactly three read-only optical media".into());
            }
            Ok(String::new())
        }
        _ => Err("invalid command".into()),
    }
}
fn main() {
    match run() {
        Ok(result) => {
            if !result.is_empty() {
                println!("{result}");
            }
        }
        Err(error) => {
            eprintln!("libvirt XML: {error}");
            std::process::exit(1);
        }
    }
}
