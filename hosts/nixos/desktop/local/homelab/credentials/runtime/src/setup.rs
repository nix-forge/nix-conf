use super::*;
fn random(n: usize) -> Result<String> {
    let mut v = vec![0; n];
    std::fs::File::open("/dev/urandom")?.read_exact(&mut v)?;
    Ok(base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(v))
}
fn origin(v: &str) -> Result<String> {
    let u = reqwest::Url::parse(v)?;
    if u.scheme() != "https"
        || u.host_str().is_none()
        || !u.username().is_empty()
        || u.password().is_some()
        || !matches!(u.path(), "" | "/")
        || u.query().is_some()
        || u.fragment().is_some()
    {
        return fail("expected credential-free HTTPS origin");
    }
    Ok(v.trim_end_matches('/').into())
}
pub async fn miniflux(a: &Args) -> Result<()> {
    a.required("identity")?;
    let plans = sealed::Plans::load(a)?;
    plans.entry("homelab-miniflux-username")?;
    plans.entry("homelab-miniflux-password")?;
    let mut env = BTreeMap::new();
    if !a.has("seal-only") {
        vault::unlocked(&mut env, false).await?;
    }
    let (u, p): (String, String) = if a.has("prompt") {
        let u = prompt("Existing Miniflux username [admin]: ", false).await?;
        (
            if u.trim().is_empty() {
                "admin".into()
            } else {
                u.trim().into()
            },
            prompt("Existing Miniflux password: ", true).await?,
        )
    } else {
        let raw = if a.has("credential-via-host") {
            command(
                &[
                    "ssh",
                    "-o",
                    "BatchMode=yes",
                    "--",
                    a.required("credential-via-host")?,
                    "ssh -o BatchMode=yes root@desktop cat /var/lib/homelab-miniflux/admin.env",
                ],
                None,
            )
            .await?
        } else {
            command(
                &["sudo", "cat", "/var/lib/homelab-miniflux/admin.env"],
                None,
            )
            .await?
        };
        let values: BTreeMap<_, _> = raw.lines().filter_map(|l| l.split_once('=')).collect();
        (
            values.get("ADMIN_USERNAME").copied().unwrap_or("").into(),
            values.get("ADMIN_PASSWORD").copied().unwrap_or("").into(),
        )
    };
    let url = format!("https://miniflux.{}", domain());
    let account = vault::Account::new("Miniflux", &url, &u, &p)?;
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(15))
        .redirect(reqwest::redirect::Policy::none())
        .build()?;
    let response: Value = client
        .get(format!("{url}/v1/me"))
        .basic_auth(&u, Some(&p))
        .send()
        .await?
        .error_for_status()?
        .json()
        .await?;
    if response["username"] != u {
        return fail("Miniflux returned another account");
    }
    println!("Existing Miniflux login verified over HTTPS");
    plans.seal(a, "homelab-miniflux-username", &u).await?;
    plans.seal(a, "homelab-miniflux-password", &p).await?;
    if !a.has("seal-only") {
        vault::reconcile(&[account], &mut env, true, None, true).await?;
    }
    Ok(())
}
pub async fn identity(a: &Args) -> Result<()> {
    for k in [
        "identity",
        "authorizer-key",
        "administrator-host",
        "session-file",
        "bootstrap-plan",
    ] {
        a.required(k)?;
    }
    let identity_url = origin(a.required("identity-url")?)?;
    let wardrobe_url = origin(a.required("wardrobe-url")?)?;
    let path = Path::new(a.required("session-file")?);
    let fd = rustix::fs::open(
        path,
        rustix::fs::OFlags::RDONLY | rustix::fs::OFlags::NOFOLLOW | rustix::fs::OFlags::NONBLOCK,
        rustix::fs::Mode::empty(),
    )?;
    let mut file = std::fs::File::from(fd);
    let metadata = file.metadata()?;
    use std::os::unix::fs::MetadataExt;
    if !metadata.is_file()
        || metadata.uid() != rustix::process::getuid().as_raw()
        || metadata.mode() & 0o077 != 0
        || metadata.nlink() != 1
    {
        return fail("session file must be private and user-owned");
    }
    let mut session = String::new();
    file.read_to_string(&mut session)?;
    if session.trim().is_empty() {
        return fail("empty session");
    }
    let mut env = BTreeMap::from([("BW_SESSION".into(), session.trim().into())]);
    vault::unlocked(&mut env, false).await?;
    let plans = sealed::Plans::load(a)?;
    // Validate all canonical IDs and source ownership before generating or mutating.
    for n in [
        "homelab-identity-realm",
        "homelab-identity-admin-env",
        "homelab-wardrowbe-env",
    ] {
        plans.entry(n)?;
    }
    let realm = plans.existing(a, "homelab-identity-realm").await?;
    let admin = plans.existing(a, "homelab-identity-admin-env").await?;
    let app = plans.existing(a, "homelab-wardrowbe-env").await?;
    if realm.is_none() && app.is_some() {
        return fail("existing application credentials require explicit migration");
    }
    let realm = if let Some(v) = realm {
        v
    } else {
        let mut v: Value = serde_json::from_str(include_str!("realm.json"))?;
        let host = identity_url.split_once("://").ok_or("origin")?.1;
        v["realm"] = json!(a.get("realm", "homelab"));
        v["webAuthnPolicyPasswordlessRpId"] = json!(host);
        v["users"][0]["email"] = json!(format!("member@{host}"));
        v["users"][0]["credentials"][0]["value"] = json!(random(32)?);
        v["clients"][0]["secret"] = json!(random(48)?);
        v["clients"][0]["redirectUris"] = json!([format!("{wardrobe_url}/api/auth/callback/oidc")]);
        v["clients"][0]["webOrigins"] = json!([wardrobe_url]);
        v["clients"][0]["attributes"]["post.logout.redirect.uris"] = json!(wardrobe_url);
        serde_json::to_string(&v)?
    };
    let document: Value = serde_json::from_str(&realm)?;
    let admin = match admin {
        Some(v) => v,
        None => format!(
            "KC_BOOTSTRAP_ADMIN_USERNAME=bootstrap\nKC_BOOTSTRAP_ADMIN_PASSWORD={}\nHOMELAB_ADMIN_USERNAME=administrator\nHOMELAB_ADMIN_PASSWORD={}\n",
            random(32)?,
            random(32)?
        ),
    };
    let app = match app {
        Some(v) => v,
        None => format!(
            "OIDC_CLIENT_ID={}\nOIDC_CLIENT_SECRET={}\nSECRET_KEY={}\nNEXTAUTH_SECRET={}\n",
            string(&document["clients"][0]["clientId"]),
            string(&document["clients"][0]["secret"]),
            random(48)?,
            random(48)?
        ),
    };
    let adm = inventory::dotenv(&admin)?;
    let accounts = [
        vault::Account::new(
            "Wardrowbe",
            &identity_url,
            string(&document["users"][0]["username"]),
            string(&document["users"][0]["credentials"][0]["value"]),
        )?,
        vault::Account::new(
            "Wardrowbe sign-in administrator",
            &format!("{identity_url}/admin/"),
            adm.get("HOMELAB_ADMIN_USERNAME")
                .map(String::as_str)
                .unwrap_or(""),
            adm.get("HOMELAB_ADMIN_PASSWORD")
                .map(String::as_str)
                .unwrap_or(""),
        )?,
    ];
    for (n, v) in [
        ("homelab-identity-realm", realm),
        ("homelab-identity-admin-env", admin),
        ("homelab-wardrowbe-env", app),
    ] {
        plans.seal(a, n, &v).await?;
    }
    vault::reconcile(&accounts, &mut env, true, None, true).await?;
    let now = std::fs::symlink_metadata(path)?;
    if now.dev() != metadata.dev() || now.ino() != metadata.ino() {
        return fail("session file changed");
    }
    std::fs::remove_file(path)?;
    println!(
        "Identity credentials sealed; both Bitwarden items synced; temporary unlock file removed"
    );
    Ok(())
}
