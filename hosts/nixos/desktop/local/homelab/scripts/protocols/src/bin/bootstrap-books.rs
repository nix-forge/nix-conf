use reqwest::{Client, Method, StatusCode};
use serde_json::{Value, json};
use std::{env, fs, path::PathBuf, time::Duration};
type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
struct Api {
    client: Client,
    base: String,
    username: String,
    password: String,
}
impl Api {
    async fn request(
        &self,
        method: Method,
        path: &str,
        body: Option<Value>,
        expected: &[u16],
    ) -> Result<Value> {
        let mut request = self.client.request(method, format!("{}{path}", self.base));
        if !self.username.is_empty() {
            request = request.basic_auth(&self.username, Some(&self.password));
        }
        if let Some(body) = body {
            request = request.json(&body);
        }
        let response = request.send().await?;
        if !expected.contains(&response.status().as_u16()) {
            return Err("Unexpected service HTTP status".into());
        }
        let bytes = response.bytes().await?;
        Ok(if bytes.is_empty() {
            Value::Null
        } else {
            serde_json::from_slice(&bytes)?
        })
    }
}
fn credential(name: &str) -> Result<String> {
    let value = fs::read_to_string(PathBuf::from(env::var("CREDENTIALS_DIRECTORY")?).join(name))?
        .trim()
        .to_owned();
    if value.is_empty() || value.contains(['\r', '\n', '\0']) {
        return Err("Invalid book credential".into());
    }
    Ok(value)
}
fn objects(value: &Value) -> Result<&Vec<Value>> {
    let array = value.as_array().ok_or("Invalid service list")?;
    if array.iter().any(|v| !v.is_object()) {
        return Err("Invalid service object".into());
    }
    Ok(array)
}
fn field<'a>(value: &'a Value, name: &str) -> Result<&'a str> {
    value[name]
        .as_str()
        .ok_or_else(|| "Invalid service field".into())
}
async fn reconcile(args: &[String]) -> Result<()> {
    if args.len() != 4
        || ![
            "DISABLED",
            "HOURLY",
            "EVERY_6H",
            "EVERY_12H",
            "DAILY",
            "WEEKLY",
        ]
        .contains(&args[3].as_str())
    {
        return Err("Invalid books arguments".into());
    }
    let port: u16 = args[0].parse()?;
    let audio_port: u16 = args[1].parse()?;
    let client = Client::builder()
        .no_proxy()
        .redirect(reqwest::redirect::Policy::none())
        .timeout(Duration::from_secs(10))
        .build()?;
    let base = format!("http://127.0.0.1:{port}");
    let admin = Api {
        client: client.clone(),
        base: base.clone(),
        username: credential("komga-admin-username")?,
        password: credential("komga-admin-password")?,
    };
    let username = credential("komga-reader-username")?;
    let password = credential("komga-reader-password")?;
    // Komga exposes no readiness notification. Retry only the safe claim GET,
    // with positive backoff under one deadline covering requests and sleeps.
    tokio::time::timeout(Duration::from_secs(120), async {
        loop {
            match client.get(format!("{base}/api/v1/claim")).send().await {
                Ok(response) => {
                    if response.status() != StatusCode::OK {
                        return Err("Komga readiness rejected".into());
                    }
                    return Ok::<(), Box<dyn std::error::Error>>(());
                }
                Err(error) if error.is_connect() || error.is_timeout() => {
                    tokio::time::sleep(Duration::from_secs(2)).await
                }
                Err(error) => return Err(error.into()),
            }
        }
    })
    .await??;
    let status = client
        .get(format!("{base}/api/v1/libraries"))
        .basic_auth(&admin.username, Some(&admin.password))
        .send()
        .await?
        .status();
    if status == StatusCode::UNAUTHORIZED || status == StatusCode::FORBIDDEN {
        let response = client
            .post(format!("{base}/api/v1/claim"))
            .header("X-Komga-Email", &admin.username)
            .header("X-Komga-Password", &admin.password)
            .send()
            .await?;
        if response.status() != StatusCode::OK {
            return Err("Komga claim rejected".into());
        }
    } else if status != StatusCode::OK {
        return Err("Komga administrator rejected".into());
    }
    let libraries = admin
        .request(Method::GET, "/api/v1/libraries", None, &[200])
        .await?;
    let matches: Vec<_> = objects(&libraries)?
        .iter()
        .filter(|v| v["name"] == "Books")
        .collect();
    if matches.len() > 1 {
        return Err("Ambiguous Books library".into());
    }
    let library = if let Some(existing) = matches.first() {
        if existing["root"] != args[2] {
            return Err("Books library has a different root".into());
        }
        if existing["scanInterval"] != args[3] {
            admin
                .request(
                    Method::PATCH,
                    &format!("/api/v1/libraries/{}", field(existing, "id")?),
                    Some(json!({"scanInterval":args[3]})),
                    &[204],
                )
                .await?;
        }
        (*existing).clone()
    } else {
        let mut defaults: Value =
            serde_json::from_str(include_str!("../../library-defaults.json"))?;
        defaults["root"] = json!(args[2]);
        defaults["scanInterval"] = json!(args[3]);
        admin
            .request(Method::POST, "/api/v1/libraries", Some(defaults), &[200])
            .await?
    };
    let library_id = field(&library, "id")?;
    let users = admin
        .request(Method::GET, "/api/v2/users", None, &[200])
        .await?;
    let matches: Vec<_> = objects(&users)?
        .iter()
        .filter(|v| v["email"] == username)
        .collect();
    if matches.len() > 1 {
        return Err("Ambiguous Komga reader".into());
    }
    let policy = json!({"roles":["PAGE_STREAMING","FILE_DOWNLOAD"],"sharedLibraries":{"all":false,"libraryIds":[library_id]}});
    if let Some(user) = matches.first() {
        let path = format!("/api/v2/users/{}", field(user, "id")?);
        let roles = user["roles"].as_array().ok_or("Invalid reader roles")?;
        let mut sorted = roles
            .iter()
            .map(|r| r.as_str().ok_or("Invalid reader role"))
            .collect::<std::result::Result<Vec<_>, _>>()?;
        sorted.sort_unstable();
        sorted.dedup();
        let ids = user["sharedLibrariesIds"]
            .as_array()
            .ok_or("Invalid library permissions")?;
        if sorted != ["FILE_DOWNLOAD", "PAGE_STREAMING"]
            || user["sharedAllLibraries"] != false
            || ids.is_empty()
            || ids.iter().any(|id| id != library_id)
        {
            admin
                .request(Method::PATCH, &path, Some(policy), &[204])
                .await?;
        }
        admin
            .request(
                Method::PATCH,
                &format!("{path}/password"),
                Some(json!({"password":password})),
                &[204],
            )
            .await?;
    } else {
        let mut body = policy;
        body["email"] = json!(username);
        body["password"] = json!(password);
        admin
            .request(Method::POST, "/api/v2/users", Some(body), &[201])
            .await?;
    }
    Api {
        client: client.clone(),
        base,
        username,
        password,
    }
    .request(Method::GET, "/api/v1/libraries", None, &[200])
    .await?;
    let audio = Api {
        client,
        base: format!("http://127.0.0.1:{audio_port}"),
        username: String::new(),
        password: String::new(),
    };
    if audio.request(Method::GET, "/status", None, &[200]).await?["isInit"] != true {
        return Err("Audiobookshelf administrator is not initialized".into());
    }
    let runtime =
        PathBuf::from(env::var("BOOKS_READY_DIR").unwrap_or_else(|_| "/run/homelab-books".into()));
    fs::create_dir_all(&runtime)?;
    fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(false)
        .open(runtime.join("ready"))?;
    Ok(())
}
#[tokio::main(flavor = "current_thread")]
async fn main() {
    if reconcile(&env::args().skip(1).collect::<Vec<_>>())
        .await
        .is_err()
    {
        eprintln!("Book bootstrap failed; credential and response details suppressed");
        std::process::exit(1);
    }
}
