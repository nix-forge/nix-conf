use reqwest::{Client, Method, StatusCode};
use serde_json::{Value, json};
use std::{env, fs, path::PathBuf, time::Duration};
type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
struct Api {
    client: Client,
    base: String,
    token: String,
}
impl Api {
    async fn request(&self, method: Method, path: &str, body: Option<Value>) -> Result<Value> {
        let mut request = self
            .client
            .request(method, format!("{}/admin{path}", self.base))
            .bearer_auth(&self.token);
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
}
async fn reconcile(args: &[String]) -> Result<()> {
    if args.len() != 2 {
        return Err("Expected identity base and Actual origin".into());
    }
    let credentials = PathBuf::from(env::var("CREDENTIALS_DIRECTORY")?);
    let read = |name: &str| -> Result<String> {
        Ok(fs::read_to_string(credentials.join(name))?
            .trim()
            .to_owned())
    };
    let admin_text = read("admin")?;
    let admin: std::collections::HashMap<_, _> = admin_text
        .lines()
        .filter_map(|line| line.split_once('='))
        .collect();
    let base = args[0].trim_end_matches('/');
    let origin = args[1].trim_end_matches('/');
    let client = Client::builder()
        .timeout(Duration::from_secs(30))
        .redirect(reqwest::redirect::Policy::none())
        .build()?;
    let response: Value = client
        .post(format!(
            "{base}/realms/master/protocol/openid-connect/token"
        ))
        .form(&[
            ("grant_type", "password"),
            ("client_id", "admin-cli"),
            (
                "username",
                *admin
                    .get("HOMELAB_ADMIN_USERNAME")
                    .ok_or("Missing administrator")?,
            ),
            (
                "password",
                *admin
                    .get("HOMELAB_ADMIN_PASSWORD")
                    .ok_or("Missing administrator password")?,
            ),
        ])
        .send()
        .await?
        .error_for_status()?
        .json()
        .await?;
    let api = Api {
        client,
        base: base.to_owned(),
        token: response["access_token"]
            .as_str()
            .ok_or("Missing access token")?
            .to_owned(),
    };
    let response = api
        .client
        .get(format!("{base}/admin/realms/actual"))
        .bearer_auth(&api.token)
        .send()
        .await?;
    if response.status() == StatusCode::NOT_FOUND {
        api.request(Method::POST, "/realms", Some(json!({"realm":"actual","enabled":true,"sslRequired":"external","registrationAllowed":false,"resetPasswordAllowed":false,"bruteForceProtected":true,"failureFactor":5,"waitIncrementSeconds":60,"maxFailureWaitSeconds":900}))).await?;
    } else {
        response.error_for_status()?;
    }
    let username = read("username")?;
    let mut url = reqwest::Url::parse(&format!("{base}/admin/realms/actual/users"))?;
    url.query_pairs_mut()
        .append_pair("username", &username)
        .append_pair("exact", "true");
    let users: Value = api
        .client
        .get(url)
        .bearer_auth(&api.token)
        .send()
        .await?
        .error_for_status()?
        .json()
        .await?;
    let users = users.as_array().ok_or("Invalid users response")?;
    if users.is_empty() {
        api.request(Method::POST, "/realms/actual/users", Some(json!({"username":username,"firstName":"Budget","lastName":"Owner","email":"owner@localhost.invalid","enabled":true,"emailVerified":true,"credentials":[{"type":"password","value":read("password")?,"temporary":false}]}))).await?;
    } else if users.len() != 1 {
        return Err("Ambiguous Actual identity".into());
    }
    // Existing passwords deliberately survive reconciliation.
    let clients = api
        .request(Method::GET, "/realms/actual/clients?clientId=actual", None)
        .await?;
    let clients = clients.as_array().ok_or("Invalid clients response")?;
    let client = json!({"clientId":"actual","enabled":true,"protocol":"openid-connect","publicClient":false,"secret":read("client-secret")?,"standardFlowEnabled":true,"directAccessGrantsEnabled":false,"serviceAccountsEnabled":false,"redirectUris":[format!("{origin}/openid/callback")],"webOrigins":[origin],"attributes":{"pkce.code.challenge.method":"S256"},"defaultClientScopes":["web-origins","profile","email","roles"]});
    match clients.as_slice() {
        [] => {
            api.request(Method::POST, "/realms/actual/clients", Some(client))
                .await?;
        }
        [existing] => {
            let id = existing["id"].as_str().ok_or("Missing client ID")?;
            if id.contains(['/', '?', '#']) {
                return Err("Invalid client ID".into());
            }
            api.request(
                Method::PUT,
                &format!("/realms/actual/clients/{id}"),
                Some(client),
            )
            .await?;
        }
        _ => return Err("Ambiguous Actual client".into()),
    }
    println!("Actual identity configuration ready");
    Ok(())
}
#[tokio::main(flavor = "current_thread")]
async fn main() {
    if reconcile(&env::args().skip(1).collect::<Vec<_>>())
        .await
        .is_err()
    {
        eprintln!("Actual identity reconciliation failed; credentials were not logged");
        std::process::exit(1);
    }
}
