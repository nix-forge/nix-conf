//! Reconcile authenticated music integrations, retaining existing user choices.
use reqwest::{Client, Method};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    env, fs,
    path::{Path, PathBuf},
    time::Duration,
};
type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
struct Bootstrap {
    client: Client,
    base: String,
    lidarr: String,
    slskd: String,
    state: PathBuf,
    credentials: PathBuf,
    quality: Value,
    downloads: String,
    music: String,
}
fn string(value: &Value) -> Result<&str> {
    value
        .as_str()
        .ok_or_else(|| "Invalid service string".into())
}
fn list(value: &Value) -> Result<&Vec<Value>> {
    value
        .as_array()
        .ok_or_else(|| "Invalid service list".into())
}
fn truth(value: &Value) -> bool {
    match value {
        Value::Null => false,
        Value::Bool(b) => *b,
        Value::String(s) => !s.is_empty(),
        Value::Number(n) => n.as_f64() != Some(0.0),
        Value::Array(v) => !v.is_empty(),
        Value::Object(v) => !v.is_empty(),
    }
}
fn marker(path: &Path) -> Option<String> {
    fs::read_to_string(path).ok().map(|v| v.trim().to_owned())
}
impl Bootstrap {
    fn credential(&self, name: &str) -> Result<String> {
        Ok(fs::read_to_string(self.credentials.join(name))?
            .trim()
            .to_owned())
    }
    async fn request(
        &self,
        method: Method,
        url: &str,
        body: Option<Value>,
        auth: Option<(&str, &str)>,
    ) -> Result<Value> {
        let mut request = self.client.request(method, url);
        if let Some((name, value)) = auth {
            request = request.header(name, value);
        }
        if let Some(body) = body {
            request = request.json(&body);
        }
        let bytes = request.send().await?.error_for_status()?.bytes().await?;
        Ok(if bytes.is_empty() {
            Value::Null
        } else {
            serde_json::from_slice(&bytes)?
        })
    }
    async fn lidarr(
        &self,
        method: Method,
        path: &str,
        body: Option<Value>,
        key: &str,
    ) -> Result<Value> {
        self.request(
            method,
            &format!("{}/api/v1/{path}", self.lidarr),
            body,
            Some(("X-Api-Key", key)),
        )
        .await
    }
    async fn app(
        &self,
        method: Method,
        path: &str,
        body: Option<Value>,
        auth: &str,
    ) -> Result<Value> {
        self.request(
            method,
            &format!("{}{path}", self.base),
            body,
            if auth.is_empty() {
                None
            } else {
                Some(("Authorization", auth))
            },
        )
        .await
    }
    async fn settings(&self, body: Value, auth: &str) -> Result<()> {
        self.app(Method::POST, "/api/settings", Some(body), auth)
            .await?;
        Ok(())
    }
    async fn quality(&self, key: &str) -> Result<Value> {
        let profiles = self
            .lidarr(Method::GET, "qualityprofile", None, key)
            .await?;
        let profiles = list(&profiles)?;
        let name = &self.quality["name"];
        let existing = profiles.iter().find(|p| p["name"] == *name);
        let template = existing
            .or_else(|| {
                profiles.iter().find(|p| {
                    p["name"].as_str().is_some_and(|n| {
                        n.eq_ignore_ascii_case(self.quality["templateName"].as_str().unwrap_or(""))
                    })
                })
            })
            .ok_or("Missing quality template")?;
        let mut profile = template.clone();
        let mut cutoff = None;
        fn select(
            item: &mut Value,
            cutoff_id: &Value,
            policy: &Value,
            cutoff: &mut Option<Value>,
        ) -> Result<()> {
            let has_children = item
                .get("items")
                .and_then(Value::as_array)
                .is_some_and(|v| !v.is_empty());
            if has_children {
                for child in item["items"]
                    .as_array_mut()
                    .ok_or("Invalid quality children")?
                {
                    select(child, cutoff_id, policy, cutoff)?;
                }
            }
            let allowed = if has_children {
                list(&item["items"])?.iter().any(|v| v["allowed"] == true)
            } else {
                list(&policy["allowedQualityNames"])?.contains(&item["quality"]["name"])
            };
            item["allowed"] = json!(allowed);
            if truth(&policy["cutoffQualityName"])
                && item["quality"]["name"] == policy["cutoffQualityName"]
            {
                if !allowed {
                    return Err("Cutoff quality not allowed".into());
                }
                *cutoff = Some(cutoff_id.clone());
            }
            Ok(())
        }
        let items = profile["items"]
            .as_array_mut()
            .filter(|v| !v.is_empty())
            .ok_or("Empty quality template")?;
        for item in items {
            let id = item["quality"].get("id").unwrap_or(&item["id"]).clone();
            select(item, &id, &self.quality, &mut cutoff)?;
        }
        if truth(&self.quality["cutoffQualityName"]) && cutoff.is_none() {
            return Err("Missing cutoff quality".into());
        }
        profile["name"] = name.clone();
        profile["upgradeAllowed"] = self.quality["upgradeAllowed"].clone();
        profile["cutoff"] = cutoff.unwrap_or_else(|| template["cutoff"].clone());
        if let Some(existing) = existing {
            if profile != *existing {
                self.lidarr(
                    Method::PUT,
                    &format!("qualityprofile/{}", existing["id"]),
                    Some(profile),
                    key,
                )
                .await?;
            }
            Ok(existing["id"].clone())
        } else {
            profile
                .as_object_mut()
                .ok_or("Invalid quality profile")?
                .remove("id");
            Ok(self
                .lidarr(Method::POST, "qualityprofile", Some(profile), key)
                .await?["id"]
                .clone())
        }
    }
    async fn metadata(&self, key: &str) -> Result<Value> {
        let profiles = self
            .lidarr(Method::GET, "metadataprofile", None, key)
            .await?;
        let name = string(&self.quality["onboarding"]["metadataProfileName"])?;
        list(&profiles)?
            .iter()
            .find(|p| {
                p["name"]
                    .as_str()
                    .is_some_and(|n| n.eq_ignore_ascii_case(name))
            })
            .map(|p| p["id"].clone())
            .ok_or_else(|| "Missing metadata profile".into())
    }
    async fn connection(&self, key: &str, current: &Value, auth: &str) -> Result<Value> {
        let mut roots = vec![json!(self.music)];
        if let Some(old) = current["rootFolderPaths"].as_array() {
            roots.extend(old.iter().filter(|v| **v != self.music).cloned());
        }
        let quality = if truth(&current["qualityProfileId"]) {
            current["qualityProfileId"].clone()
        } else {
            self.quality(key).await?
        };
        let metadata = if truth(&current["metadataProfileId"]) {
            current["metadataProfileId"].clone()
        } else {
            self.metadata(key).await?
        };
        let desired = json!({"url":self.lidarr,"apiKey":key,"enabled":true,"rootFolderPaths":roots,"qualityProfileId":quality,"metadataProfileId":metadata,"defaultMonitorOption":current.get("defaultMonitorOption").unwrap_or(&self.quality["onboarding"]["defaultMonitorOption"]),"searchOnAdd":current.get("searchOnAdd").unwrap_or(&self.quality["onboarding"]["searchOnAdd"])});
        let fields = desired.as_object().ok_or("Invalid connection")?;
        if fields.iter().any(|(k, v)| current.get(k) != Some(v)) {
            self.settings(json!({"integrations":{"lidarr":desired}}), auth)
                .await?;
            let confirmed = self.app(Method::GET, "/api/settings", None, auth).await?;
            if fields.iter().any(|(k, v)| {
                k != "apiKey" && confirmed["integrations"]["lidarr"].get(k) != Some(v)
            }) {
                return Err("Lidarr connection not confirmed".into());
            }
        }
        let mut merged = current.as_object().cloned().unwrap_or_default();
        merged.extend(fields.clone());
        Ok(Value::Object(merged))
    }
    async fn migrate_quality(&self, key: &str, current: &Value, auth: &str) -> Result<()> {
        let path = self.state.join("lidarr-quality-profile-v1");
        let previous = marker(&path).map(|s| s.parse::<i64>()).transpose()?;
        let profiles = self
            .lidarr(Method::GET, "qualityprofile", None, key)
            .await?;
        let old_id = &current["qualityProfileId"];
        let old = list(&profiles)?.iter().find(|p| p["id"] == *old_id);
        if let Some(id) = previous {
            if *old_id != id || old.is_some_and(|p| p["name"] == self.quality["name"]) {
                return Ok(());
            }
        } else if let Some(old) = old {
            let name = string(&old["name"])?.to_lowercase();
            if name != "lossless"
                && name != "flac"
                && name != string(&self.quality["name"])?.to_lowercase()
            {
                return Ok(());
            }
        }
        let id = self.quality(key).await?;
        if *old_id != id {
            let artists = self.lidarr(Method::GET, "artist", None, key).await?;
            for artist in list(&artists)? {
                let path = artist["path"]
                    .as_str()
                    .filter(|s| !s.is_empty())
                    .unwrap_or("/");
                if artist["qualityProfileId"] == *old_id && Path::new(path).starts_with(&self.music)
                {
                    let mut desired = artist.clone();
                    desired["qualityProfileId"] = id.clone();
                    self.lidarr(
                        Method::PUT,
                        &format!("artist/{}", artist["id"]),
                        Some(desired),
                        key,
                    )
                    .await?;
                }
            }
            self.settings(
                json!({"integrations":{"lidarr":{"qualityProfileId":id}}}),
                auth,
            )
            .await?;
        }
        fs::write(path, format!("{id}\n"))?;
        Ok(())
    }
    async fn webhook(&self, key: &str, auth: &str) -> Result<()> {
        let app_key = self
            .app(Method::GET, "/api/auth/api-key", None, auth)
            .await?;
        let notifications = self.lidarr(Method::GET, "notification", None, key).await?;
        let existing = list(&notifications)?
            .iter()
            .find(|v| v["name"] == "Aurral imports");
        let schema = self
            .lidarr(Method::GET, "notification/schema", None, key)
            .await?;
        let template = list(&schema)?
            .iter()
            .find(|v| v["implementation"] == "Webhook")
            .ok_or("Missing webhook schema")?;
        let mut desired = existing.unwrap_or(template).clone();
        desired["name"] = json!("Aurral imports");
        desired["onReleaseImport"] = json!(true);
        desired["onUpgrade"] = json!(true);
        for field in desired["fields"]
            .as_array_mut()
            .ok_or("Invalid webhook fields")?
        {
            match field["name"].as_str() {
                Some("url") => field["value"] = json!(format!("{}/api/webhooks/lidarr", self.base)),
                Some("method") => field["value"] = json!(1),
                Some("headers") => {
                    field["value"] = json!([{"key":"X-Api-Key","value":app_key["apiKey"]}])
                }
                _ => (),
            }
        }
        self.lidarr(
            Method::POST,
            "notification/test",
            Some(desired.clone()),
            key,
        )
        .await?;
        if existing != Some(&desired) {
            let path = existing.map_or_else(
                || "notification".into(),
                |v| format!("notification/{}", v["id"]),
            );
            self.lidarr(
                if existing.is_some() {
                    Method::PUT
                } else {
                    Method::POST
                },
                &path,
                Some(desired),
                key,
            )
            .await?;
        }
        Ok(())
    }
    async fn scrobbling(&self, identity: &Value, auth: &str) -> Result<()> {
        let token = identity["token"].as_str().unwrap_or("").trim();
        let username = identity["listenbrainzUsername"]
            .as_str()
            .unwrap_or("")
            .trim();
        if token.is_empty() || username.is_empty() {
            return Ok(());
        }
        let fingerprint = format!(
            "{}",
            base16ct::HexDisplay(&Sha256::digest(format!("{username}\0{token}")))
        );
        let receipt: Value =
            serde_json::from_slice(&fs::read(env::var("LISTENBRAINZ_IDENTITY_RECEIPT")?)?)?;
        if receipt["username"] != username || receipt["fingerprint"] != fingerprint {
            return Err("ListenBrainz receipt mismatch".into());
        }
        let path = self.state.join("listenbrainz-scrobbling-profile");
        let status = self
            .app(Method::GET, "/api/scrobbling/status", None, auth)
            .await?;
        if marker(&path).as_deref() == Some(&fingerprint)
            && truth(&status["listenbrainz"]["connected"])
            && status["listenbrainz"]["displayName"] == username
        {
            return Ok(());
        }
        let linked = self
            .app(
                Method::PUT,
                "/api/scrobbling/listenbrainz/link",
                Some(json!({"token":token})),
                auth,
            )
            .await?;
        if !truth(&linked["connected"]) || linked["displayName"] != username {
            return Err("ListenBrainz verification failed".into());
        }
        fs::write(path, format!("{fingerprint}\n"))?;
        Ok(())
    }
    async fn run(&self) -> Result<()> {
        let key = self.credential("lidarr-api-key")?;
        if key.is_empty() {
            return Err("Empty Lidarr key".into());
        }
        if env::var("AURRAL_QUALITY_ONLY").as_deref() == Ok("1") {
            self.quality(&key).await?;
            println!("Lidarr music quality profile is ready");
            return Ok(());
        }
        self.client
            .get(format!("{}/api/health/live", self.base))
            .timeout(Duration::from_secs(2))
            .send()
            .await?
            .error_for_status()?;
        let folders = self
            .client
            .get(format!("{}/api/v1/rootfolder", self.lidarr))
            .header("X-Api-Key", &key)
            .timeout(Duration::from_secs(2))
            .send()
            .await?
            .error_for_status()?
            .json::<Value>()
            .await?;
        if !list(&folders)?.iter().any(|v| {
            v["path"]
                .as_str()
                .is_some_and(|p| Path::new(p) == Path::new(&self.music))
        }) {
            return Err("Missing Lidarr music root".into());
        }
        let bootstrap = self
            .app(Method::GET, "/api/health/bootstrap", None, "")
            .await?;
        let onboarding = truth(&bootstrap["onboardingRequired"]);
        let metadata_marker = self.state.join("library-metadata-version");
        let mut refresh =
            onboarding || marker(&metadata_marker).as_deref() != Some("shared-music-root-v2");
        if onboarding {
            self.app(Method::POST,"/api/onboarding/complete",Some(json!({"authUser":self.credential("aurral-admin-username")?,"authPassword":self.credential("aurral-admin-password")?,"security":{"localNetworkBypass":{"enabled":self.quality["onboarding"]["localNetworkBypass"]}},"downloadFolderPath":self.downloads})),"").await?;
        }
        let identity: Value =
            serde_json::from_slice(&fs::read(self.credentials.join("listenbrainz-identity"))?)?;
        let username = identity["listenbrainzUsername"]
            .as_str()
            .unwrap_or("")
            .trim();
        let history_marker = self.state.join("listenbrainz-profile");
        let has_password = self.credentials.join("aurral-admin-password").exists();
        let configure_history = !username.is_empty()
            && has_password
            && marker(&history_marker).as_deref() != Some(username);
        let slskd_text = self.credential("slskd-settings")?;
        let slskd_key = slskd_text
            .lines()
            .filter_map(|line| line.split_once('='))
            .find(|(name, _)| name.trim() == "SLSKD_API_KEY")
            .map(|(_, value)| value.trim().trim_matches(['\'', '"']))
            .filter(|v| !v.is_empty())
            .ok_or("Missing slskd key")?;
        let fingerprint = format!(
            "{}",
            base16ct::HexDisplay(&Sha256::digest(format!("{}\0{slskd_key}", self.slskd)))
        );
        let slskd_marker = self.state.join("slskd-profile");
        let configure_slskd =
            has_password && marker(&slskd_marker).as_deref() != Some(&fingerprint);
        if configure_history || configure_slskd || has_password {
            let login=self.app(Method::POST,"/api/auth/login",Some(json!({"username":self.credential("aurral-admin-username")?,"password":self.credential("aurral-admin-password")?})),"").await?;
            let auth = format!("Bearer {}", string(&login["token"])?);
            let settings = self.app(Method::GET, "/api/settings", None, &auth).await?;
            if env::var("AURRAL_LIDARR_WEBHOOK").as_deref() == Ok("1") {
                self.webhook(&key, &auth).await?;
            }
            let published = &settings["integrations"]["navidrome"];
            if ["url", "username", "password"]
                .iter()
                .any(|k| truth(&published[k]))
            {
                self.settings(
                    json!({"integrations":{"navidrome":{"url":"","username":"","password":""}}}),
                    &auth,
                )
                .await?;
                let confirmed = self.app(Method::GET, "/api/settings", None, &auth).await?;
                if ["url", "username", "password"]
                    .iter()
                    .any(|k| truth(&confirmed["integrations"]["navidrome"][k]))
                {
                    return Err("Navidrome publishing credentials not cleared".into());
                }
            }
            match fs::remove_file(self.state.join("navidrome-profile")) {
                Ok(()) => (),
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => (),
                Err(e) => return Err(e.into()),
            }
            if settings["downloadFolderPath"] != self.downloads {
                self.settings(json!({"downloadFolderPath":self.downloads}), &auth)
                    .await?;
                refresh = true;
            }
            let previous = &settings["integrations"]["lidarr"];
            let current = self.connection(&key, previous, &auth).await?;
            self.migrate_quality(&key, &current, &auth).await?;
            if previous["rootFolderPaths"] != current["rootFolderPaths"] {
                refresh = true;
            }
            if configure_history {
                let history = self
                    .app(
                        Method::PATCH,
                        "/api/users/me/listening-history",
                        Some(json!({"listenbrainz":username})),
                        &auth,
                    )
                    .await?;
                if history["listenbrainz"] != username {
                    return Err("History identity not confirmed".into());
                }
                fs::write(history_marker, format!("{username}\n"))?;
            }
            self.scrobbling(&identity, &auth).await?;
            if configure_slskd {
                let saved = &settings["integrations"]["slskd"];
                let mut desired = if !slskd_marker.exists() && !truth(&saved["url"]) {
                    let mut value = self.quality["slskd"].clone();
                    value["enabled"] = json!(true);
                    value
                } else {
                    saved.clone()
                };
                if !desired.is_object() {
                    desired = json!({});
                }
                desired["url"] = json!(self.slskd);
                desired["apiKey"] = json!(slskd_key);
                self.settings(json!({"integrations":{"slskd":desired}}), &auth)
                    .await?;
                fs::write(slskd_marker, format!("{fingerprint}\n"))?;
            }
            if refresh {
                let refreshed = self
                    .app(
                        Method::POST,
                        "/api/library/refresh",
                        Some(json!({"mode":"full"})),
                        &auth,
                    )
                    .await?;
                if refreshed["queued"] != true {
                    return Err("Library refresh not queued".into());
                }
                fs::write(metadata_marker, "shared-music-root-v2\n")?;
            }
        }
        println!("Aurral onboarding and music integrations are ready");
        Ok(())
    }
}
async fn run() -> Result<()> {
    let args: Vec<_> = env::args().skip(1).collect();
    if args.len() != 2 {
        return Err("Expected downloads and music roots".into());
    }
    Bootstrap {
        client: Client::builder()
            .timeout(Duration::from_secs(10))
            .redirect(reqwest::redirect::Policy::none())
            .build()?,
        base: env::var("AURRAL_URL")?,
        lidarr: env::var("LIDARR_URL")?,
        slskd: env::var("SLSKD_URL")?,
        state: env::var("AURRAL_DATA_DIR")?.into(),
        credentials: env::var("CREDENTIALS_DIRECTORY")?.into(),
        quality: serde_json::from_slice(&fs::read(env::var("AURRAL_QUALITY_POLICY")?)?)?,
        downloads: args[0].clone(),
        music: args[1].clone(),
    }
    .run()
    .await
}
#[tokio::main(flavor = "current_thread")]
async fn main() {
    if run().await.is_err() {
        eprintln!("Aurral bootstrap failed; sensitive details suppressed");
        std::process::exit(1);
    }
}
