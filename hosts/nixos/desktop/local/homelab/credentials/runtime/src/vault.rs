use super::*;
#[derive(Clone)]
pub struct Account {
    pub name: String,
    pub url: String,
    pub username: String,
    pub password: String,
}
impl Account {
    pub fn new(name: &str, url: &str, u: &str, p: &str) -> Result<Self> {
        if p.is_empty()
            || (name != "Dashboard" && u.is_empty())
            || [u, p].iter().any(|s| s.contains(['\r', '\n', '\0']))
        {
            return fail("invalid credential");
        }
        Ok(Self {
            name: name.into(),
            url: url.into(),
            username: u.into(),
            password: p.into(),
        })
    }
}
pub fn canonical(n: &str) -> &str {
    match n {
        "Homelab identity" => "Wardrowbe",
        "Homelab identity administrator" => "Wardrowbe sign-in administrator",
        _ => n,
    }
}
fn same_uri(a: &str, b: &str) -> bool {
    a.trim_end_matches('/') == b.trim_end_matches('/')
}
fn matches(i: &Value, a: &Account) -> bool {
    i["type"] == 1
        && i["deletedDate"].is_null()
        && if a.url.is_empty() {
            i["name"] == a.name && array(&i["login"]["uris"]).is_empty()
        } else {
            array(&i["login"]["uris"])
                .iter()
                .any(|u| same_uri(string(&u["uri"]), &a.url))
        }
}
fn reserve(
    claims: &mut BTreeMap<String, usize>,
    items: &[Value],
    accounts: &[Account],
    i: usize,
    a: usize,
) -> Result<()> {
    let id = string(&items[i]["id"]);
    if id.is_empty() {
        return fail("missing item ID");
    }
    if let Some(prev) = claims.get(id)
        && (accounts[*prev].username != accounts[a].username
            || accounts[*prev].password != accounts[a].password)
    {
        return fail("conflicting shared vault item; split entries before rerunning");
    }
    claims.insert(id.into(), a);
    Ok(())
}
fn unique(c: Vec<usize>) -> Result<Option<usize>> {
    if c.len() > 1 {
        fail("ambiguous vault items; resolve duplicates")
    } else {
        Ok(c.first().copied())
    }
}
fn plan(items: &[Value], accounts: &[Account]) -> Result<Vec<Option<usize>>> {
    let mut claims = BTreeMap::new();
    let mut selected = vec![None; accounts.len()];
    for phase in 0..3 {
        for (a, account) in accounts.iter().enumerate() {
            if selected[a].is_some() {
                continue;
            }
            let c = items
                .iter()
                .enumerate()
                .filter(|(_, i)| matches(i, account))
                .filter(|(_, i)| match phase {
                    0 => string(&i["login"]["username"]) == account.username,
                    1 => {
                        !claims.contains_key(string(&i["id"]))
                            && i["login"]["password"] == account.password
                    }
                    _ => {
                        !claims.contains_key(string(&i["id"]))
                            && canonical(string(&i["name"])) == account.name
                    }
                })
                .map(|(i, _)| i)
                .collect();
            if let Some(i) = unique(c)? {
                reserve(&mut claims, items, accounts, i, a)?;
                selected[a] = Some(i);
            }
        }
    }
    Ok(selected)
}
// Bootstrap import keeps existing URI policy; the full importer manages autofill.
fn setup_updated(original: Option<&Value>, a: &Account) -> Result<Value> {
    let mut v = original.cloned().unwrap_or_else(
        || json!({"type":1,"name":a.name,"login":{"uris":[{"uri":a.url,"match":0}]}}),
    );
    if !v["login"].is_object() {
        return fail("invalid vault login");
    }
    v["login"]["username"] = json!(a.username);
    v["login"]["password"] = json!(a.password);
    Ok(v)
}
fn uri(uris: &mut Vec<Value>, url: &str, m: u8) {
    if let Some(v) = uris.iter_mut().find(|v| same_uri(string(&v["uri"]), url)) {
        v["match"] = json!(m);
    } else {
        uris.push(json!({"uri":url,"match":m}));
    }
}
fn updated(original: Option<&Value>, a: &Account) -> Result<Value> {
    let mut v = original
        .cloned()
        .unwrap_or(json!({"type":1,"name":a.name,"login":{}}));
    if canonical(string(&v["name"])) == a.name {
        v["name"] = json!(a.name);
    }
    if v["login"].is_null() {
        v["login"] = json!({});
    }
    v["login"]["username"] = if a.username.is_empty() {
        Value::Null
    } else {
        json!(a.username)
    };
    v["login"]["password"] = json!(a.password);
    if v["login"]["uris"].is_null() {
        v["login"]["uris"] = json!([]);
    }
    let uris = v["login"]["uris"]
        .as_array_mut()
        .ok_or("invalid URI list")?;
    if !a.url.is_empty() {
        uri(
            uris,
            &a.url,
            match a.name.as_str() {
                "Wardrowbe" => 3,
                "Wardrowbe sign-in administrator" => 2,
                _ => 1,
            },
        );
    }
    match a.name.as_str() {
        "Miniflux" => uri(uris, &format!("https://news.{}", domain()), 1),
        "Wardrowbe" => uri(
            uris,
            &format!("https://identity.{}/realms/homelab/", domain()),
            2,
        ),
        "Actual" => uri(
            uris,
            &format!("https://identity.{}/realms/actual/", domain()),
            2,
        ),
        _ => (),
    };
    Ok(v)
}
async fn bw(args: &[&str], input: Option<&str>, env: &BTreeMap<String, String>) -> Result<String> {
    let mut v = vec!["bw"];
    v.extend(args);
    run(&v, input.map(str::as_bytes), env).await
}
pub async fn unlocked(env: &mut BTreeMap<String, String>, interactive: bool) -> Result<()> {
    if !interactive
        && env
            .get("BW_SESSION")
            .map(String::as_str)
            .unwrap_or("")
            .is_empty()
        && std::env::var("BW_SESSION").unwrap_or_default().is_empty()
    {
        return fail("a private Bitwarden session is required");
    }
    let status: Value = serde_json::from_str(&bw(&["status"], None, env).await?)?;
    if status["status"] == "unauthenticated" {
        return fail("sign in using bw login first");
    }
    if status["status"] != "unlocked" {
        if !interactive {
            return fail("Bitwarden must be unlocked");
        }
        let mut private = env.clone();
        private.insert(
            "HOMELAB_BW_MASTER_PASSWORD".into(),
            prompt("Bitwarden master password: ", true).await?,
        );
        let session = bw(
            &[
                "unlock",
                "--raw",
                "--passwordenv",
                "HOMELAB_BW_MASTER_PASSWORD",
            ],
            None,
            &private,
        )
        .await?;
        env.insert("BW_SESSION".into(), session.trim().into());
    }
    let status: Value = serde_json::from_str(&bw(&["status"], None, env).await?)?;
    if status["status"] != "unlocked" {
        return fail("Bitwarden remains locked");
    }
    Ok(())
}
fn verify(actual: &Value, expected: &Value, original: Option<&Value>) -> Result<()> {
    if actual["type"] != 1
        || !actual["deletedDate"].is_null()
        || actual["name"] != expected["name"]
        || string(&actual["login"]["username"]) != string(&expected["login"]["username"])
        || actual["login"]["password"] != expected["login"]["password"]
    {
        return fail("vault credential readback failed");
    }
    for u in array(&expected["login"]["uris"]) {
        if !array(&actual["login"]["uris"])
            .iter()
            .any(|v| same_uri(string(&v["uri"]), string(&u["uri"])) && v["match"] == u["match"])
        {
            return fail("vault URI readback failed");
        }
    }
    if let Some(o) = original {
        for k in ["fido2Credentials", "totp"] {
            if actual["login"][k] != o["login"][k] {
                return fail("preserved login field differs");
            }
        }
        for k in [
            "notes",
            "fields",
            "folderId",
            "attachments",
            "organizationId",
        ] {
            if actual[k] != o[k] {
                return fail("preserved vault field differs");
            }
        }
    }
    Ok(())
}
pub async fn reconcile(
    accounts: &[Account],
    env: &mut BTreeMap<String, String>,
    apply: bool,
    receipt: Option<&Path>,
    simple: bool,
) -> Result<()> {
    unlocked(env, !simple).await?;
    bw(&["sync"], None, env).await?;
    let items: Vec<Value> = serde_json::from_str(&bw(&["list", "items"], None, env).await?)?;
    let selected = if simple {
        let mut s = Vec::new();
        for a in accounts {
            let candidates = items
                .iter()
                .enumerate()
                .filter(|(_, i)| matches(i, a))
                .map(|(i, _)| i)
                .collect();
            let i = unique(candidates)?;
            if let Some(i) = i {
                let l = &items[i]["login"];
                if !string(&l["username"]).is_empty() && l["username"] != a.username {
                    return fail("different vault username");
                }
                if (l["username"] != a.username || l["password"] != a.password)
                    && !array(&l["fido2Credentials"]).is_empty()
                {
                    return fail("update passkey item manually");
                }
            }
            s.push(i);
        }
        s
    } else {
        plan(&items, accounts)?
    };
    let mut groups: Vec<(Vec<usize>, Option<usize>, Value)> = Vec::new();
    for (a, sel) in selected.iter().enumerate() {
        if let Some(g) = groups.iter_mut().find(|g| sel.is_some() && g.1 == *sel) {
            if accounts[g.0[0]].username != accounts[a].username
                || accounts[g.0[0]].password != accounts[a].password
            {
                return fail("conflicting shared item");
            }
            g.0.push(a);
            g.2 = if simple {
                setup_updated(Some(&g.2), &accounts[a])?
            } else {
                updated(Some(&g.2), &accounts[a])?
            };
        } else {
            groups.push((
                vec![a],
                *sel,
                if simple {
                    setup_updated(sel.map(|i| &items[i]), &accounts[a])?
                } else {
                    updated(sel.map(|i| &items[i]), &accounts[a])?
                },
            ));
        }
    }
    let mut saved = Vec::new();
    for (group, sel, expected) in &groups {
        let original = sel.map(|i| &items[i]);
        let changed = original != Some(expected);
        for a in group {
            println!(
                "{}: {}",
                if original.is_none() {
                    "Create"
                } else if changed {
                    "Update"
                } else {
                    "Current"
                },
                accounts[*a].name
            );
        }
        if !apply {
            continue;
        }
        let id = if changed {
            let payload = encode(&serde_json::to_vec(expected)?);
            let response = if let Some(o) = original {
                bw(&["edit", "item", string(&o["id"])], Some(&payload), env).await?
            } else {
                bw(&["create", "item"], Some(&payload), env).await?
            };
            let v: Value = serde_json::from_str(&response)?;
            string(&v["id"]).to_owned()
        } else {
            string(&expected["id"]).to_owned()
        };
        if id.is_empty() {
            return fail("missing saved ID");
        }
        saved.push((group, id, expected, original));
    }
    if !apply {
        println!(
            "Plan: {} logins; other vault items left untouched; no vault changes",
            accounts.len()
        );
        return Ok(());
    }
    bw(&["sync"], None, env).await?;
    for (group, id, expected, original) in &saved {
        let item: Value = serde_json::from_str(&bw(&["get", "item", id], None, env).await?)?;
        verify(&item, expected, *original)?;
        for a in *group {
            println!("Verified: {}", accounts[*a].name);
        }
    }
    if let Some(path) = receipt {
        let path = if let Some(rest) = path.to_str().and_then(|s| s.strip_prefix("~/")) {
            PathBuf::from(std::env::var("HOME")?).join(rest)
        } else {
            path.to_owned()
        };
        let parent = path.parent().ok_or("missing receipt parent")?;
        use std::os::unix::fs::DirBuilderExt;
        let mut d = std::fs::DirBuilder::new();
        d.recursive(true).mode(0o700).create(parent)?;
        let mut previous = if path.exists() {
            read_json(&path)?
        } else {
            json!({})
        };
        let mut entries: BTreeMap<String, Value> = array(&previous["accounts"])
            .iter()
            .map(|v| (string(&v["name"]).into(), v.clone()))
            .collect();
        let timestamp = command(&["date", "-u", "+%Y-%m-%dT%H:%M:%SZ"], None)
            .await?
            .trim()
            .to_owned();
        for (group, id, _, _) in &saved {
            for a in *group {
                entries.insert(accounts[*a].name.clone(),json!({"name":accounts[*a].name,"itemId":id,"verified":true,"verifiedAt":timestamp}));
            }
        }
        previous["verifiedAt"] = json!(timestamp);
        previous["accounts"] = json!(entries.into_values().collect::<Vec<_>>());
        let mut tmp = tempfile::NamedTempFile::new_in(parent)?;
        tmp.write_all(&serde_json::to_vec_pretty(&previous)?)?;
        tmp.as_file().sync_all()?;
        tmp.persist(path)?;
    }
    Ok(())
}
