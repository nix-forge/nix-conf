use super::*;
pub fn dotenv(text: &str) -> Result<BTreeMap<String, String>> {
    let mut out = BTreeMap::new();
    for l in text
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
    {
        let (k, v) = l.split_once('=').ok_or("invalid dotenv")?;
        let tokens = shell_words::split(v)?;
        out.insert(
            k.strip_prefix("export ").unwrap_or(k).into(),
            if tokens.len() == 1 {
                tokens[0].clone()
            } else {
                v.into()
            },
        );
    }
    Ok(out)
}
fn value(values: &BTreeMap<String, String>, expr: &str) -> Result<String> {
    if expr.is_empty() {
        return Ok(String::new());
    }
    let (source, key) = expr.split_once('#').unwrap_or((expr, ""));
    let raw = values.get(source).ok_or("missing source")?;
    if key.is_empty() {
        return Ok(raw.clone());
    }
    if source == "homelab-identity-realm" {
        let v: Value = serde_json::from_str(raw)?;
        return Ok(if key == "username" {
            string(&v["users"][0]["username"]).into()
        } else {
            let passwords: Vec<_> = array(&v["users"][0]["credentials"])
                .iter()
                .filter(|v| v["type"] == "password")
                .collect();
            if passwords.len() != 1 {
                return fail("ambiguous realm password");
            }
            string(&passwords[0]["value"]).into()
        });
    }
    if source == "music-discovery-listenbrainz-identity" {
        let v: Value = serde_json::from_str(raw)?;
        return Ok(string(&v[key]).into());
    }
    Ok(dotenv(raw)?.get(key).cloned().unwrap_or_default())
}
pub async fn main(a: &Args, fresh: bool) -> Result<()> {
    let sources: Value = serde_json::from_str(include_str!("sources.json"))?;
    let descriptors: Vec<Value> = serde_json::from_str(include_str!("accounts.json"))?;
    let mut only: std::collections::BTreeSet<String> = a
        .values
        .get("only")
        .into_iter()
        .flatten()
        .map(|s| vault::canonical(s).into())
        .collect();
    if fresh {
        only.insert("FreshRSS".into());
    }
    if only.iter().any(|n| sources.get(n).is_none()) {
        return fail("unknown account selector");
    }
    let mut required = std::collections::BTreeSet::new();
    for (name, ss) in sources.as_object().ok_or("invalid inventory")? {
        if only.is_empty() || only.contains(name) {
            for s in array(ss) {
                required.insert(string(s).to_owned());
            }
        }
    }
    let mut values = BTreeMap::new();
    let host = a.get("credential-via-host", "macbook-pro-m4");
    for target in ["desktop", "raspberry-pi"] {
        let names: Vec<_> = required
            .iter()
            .filter(|n| {
                n.starts_with("homebridge-ui-")
                    || n.starts_with("homebridge-vesync-")
                    || n.starts_with("scrypted-ui-")
            })
            .collect();
        let names: Vec<&String> = if target == "raspberry-pi" {
            names
        } else {
            required.iter().filter(|n| !names.contains(n)).collect()
        };
        if names.is_empty() {
            continue;
        }
        let base = format!("/run/nix-seal/system/services/current/ianhollow/hosts/nixos/{target}");
        let remote = format!(
            "bash -s -- {} {}",
            quote(&base),
            names.iter().map(|s| quote(s)).collect::<Vec<_>>().join(" ")
        );
        let hop = format!(
            "ssh -o BatchMode=yes {} {}",
            quote(&format!("root@{target}")),
            quote(&remote)
        );
        let output = command(
            &["ssh", "-o", "BatchMode=yes", "--", host, &hop],
            Some(include_str!("../../remote-read-sources.sh")),
        )
        .await?;
        for line in output.lines() {
            let (n, v) = line.split_once('\t').ok_or("invalid credential response")?;
            if !names.iter().any(|s| s.as_str() == n) || values.contains_key(n) {
                return fail("unexpected or duplicate source");
            }
            values.insert(
                n.into(),
                String::from_utf8(decode(v)?)?
                    .trim_end_matches('\n')
                    .to_owned(),
            );
        }
    }
    if required.iter().any(|n| !values.contains_key(n)) {
        return fail("missing credential source");
    }
    let mut accounts = Vec::new();
    let mut identities = std::collections::BTreeSet::new();
    for d in descriptors {
        let name = string(&d["name"]);
        if !only.is_empty() && !only.contains(name) {
            continue;
        }
        let u = value(&values, string(&d["username"]))?;
        let p = value(&values, string(&d["password"]))?;
        let url = string(&d["url"]).replace("DOMAIN", domain());
        if !identities.insert((url.clone(), u.clone())) {
            return fail("duplicate managed identity");
        }
        accounts.push(vault::Account::new(name, &url, &u, &p)?);
    }
    if a.has("dry-run") {
        for account in &accounts {
            println!("Ready: {} — {}", account.name, account.url);
        }
        println!(
            "Validated {} deployed logins; no vault changes",
            accounts.len()
        );
        return Ok(());
    }
    vault::reconcile(
        &accounts,
        &mut BTreeMap::new(),
        a.has("apply"),
        Some(Path::new(a.get(
            "receipt",
            "~/.local/state/homelab-bitwarden/import.json",
        ))),
        false,
    )
    .await
}
