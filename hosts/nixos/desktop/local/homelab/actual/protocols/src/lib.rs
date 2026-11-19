use reqwest::{Client, Url};
use scraper::{Html, Selector};
use serde_json::{Value, json};
use std::{collections::BTreeMap, env, fs, io::Write, path::Path, time::Duration};
type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
fn same_authority(url: &Url, expected: &Url) -> bool {
    url.host_str() == expected.host_str()
        && url.port_or_known_default() == expected.port_or_known_default()
        && url.username().is_empty()
        && url.password().is_none()
}
pub async fn login(args: &[String]) -> Result<()> {
    if args.len() != 3 {
        return Err("Expected username, password and token paths".into());
    }
    login_with_origins(
        args,
        &env::var("ACTUAL_SERVER_URL")?,
        &env::var("ACTUAL_IDENTITY_URL")?,
    )
    .await
}
pub async fn login_with_origins(
    args: &[String],
    server_origin: &str,
    identity_origin: &str,
) -> Result<()> {
    if args.len() != 3 {
        return Err("Expected username, password and token paths".into());
    }
    let server = Url::parse(server_origin)?;
    let identity = Url::parse(identity_origin)?;
    if server.scheme() != "https" || identity.scheme() != "https" {
        return Err("HTTPS origins required".into());
    }
    let redirect_server = server.clone();
    let redirect_identity = identity.clone();
    let client = Client::builder()
        .timeout(Duration::from_secs(30))
        .cookie_store(true)
        .redirect(reqwest::redirect::Policy::custom(move |attempt| {
            let url = attempt.url();
            if attempt.previous().len() >= 10
                || url.scheme() != "https"
                || (!same_authority(url, &redirect_server)
                    && !same_authority(url, &redirect_identity))
            {
                attempt.stop()
            } else {
                attempt.follow()
            }
        }))
        .build()?;
    let response: Value = client
        .post(server.join("/account/login")?)
        .json(&json!({"loginMethod":"openid","returnUrl":server_origin}))
        .send()
        .await?
        .error_for_status()?
        .json()
        .await?;
    let url = Url::parse(
        response["data"]["returnUrl"]
            .as_str()
            .ok_or("Missing login URL")?,
    )?;
    if url.scheme() != "https" || !same_authority(&url, &identity) {
        return Err("Unexpected identity provider".into());
    }
    let response = client.get(url).send().await?.error_for_status()?;
    if !same_authority(response.url(), &identity) {
        return Err("Unexpected identity form origin".into());
    }
    let html = Html::parse_document(&response.text().await?);
    let form_selector =
        Selector::parse("form#kc-form-login").map_err(|_| "Invalid form selector")?;
    let input_selector =
        Selector::parse("input[type=hidden][name]").map_err(|_| "Invalid input selector")?;
    let form = html
        .select(&form_selector)
        .next()
        .ok_or("Missing login form")?;
    let action = Url::parse(form.value().attr("action").ok_or("Missing form action")?)?;
    if action.scheme() != "https" || !same_authority(&action, &identity) {
        return Err("Unexpected login form".into());
    }
    let mut fields = BTreeMap::new();
    for input in html.select(&input_selector) {
        if let Some(name) = input.value().attr("name") {
            fields.insert(
                name.to_owned(),
                input.value().attr("value").unwrap_or("").to_owned(),
            );
        }
    }
    fields.insert(
        "username".into(),
        fs::read_to_string(&args[0])?.trim().to_owned(),
    );
    fields.insert(
        "password".into(),
        fs::read_to_string(&args[1])?.trim().to_owned(),
    );
    let response = client
        .post(action)
        .form(&fields)
        .send()
        .await?
        .error_for_status()?;
    let final_url = response.url();
    if !same_authority(final_url, &server) || final_url.path() != "/openid-cb" {
        return Err("Login did not complete".into());
    }
    let token = final_url
        .query_pairs()
        .find(|(key, _)| key == "token")
        .map(|(_, v)| v.into_owned())
        .filter(|v| !v.is_empty())
        .ok_or("Missing session token")?;
    let destination = Path::new(&args[2]);
    let mut temporary =
        tempfile::NamedTempFile::new_in(destination.parent().ok_or("Missing token directory")?)?;
    temporary.write_all(token.as_bytes())?;
    temporary.as_file().sync_all()?;
    temporary.persist(destination)?;
    Ok(())
}
