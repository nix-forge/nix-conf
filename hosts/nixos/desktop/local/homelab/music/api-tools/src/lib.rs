//! Bounded JSON clients for service-local reconciliation; no response diagnostics.
pub mod account_pty;
use reqwest::{Client, Method};
use serde_json::Value;
use std::{error::Error, path::PathBuf, time::Duration};
pub type Result<T> = std::result::Result<T, Box<dyn Error>>;
pub fn client(timeout: Duration, local: bool) -> Result<Client> {
    let builder = Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .timeout(timeout);
    Ok(if local { builder.no_proxy() } else { builder }.build()?)
}
pub async fn request(
    client: &Client,
    url: &str,
    method: Method,
    payload: Option<&Value>,
    headers: &[(&str, &str)],
) -> Result<Value> {
    let mut request = client.request(method, url);
    if let Some(payload) = payload {
        request = request.json(payload);
    }
    for (name, value) in headers {
        request = request.header(*name, *value);
    }
    let response = request.send().await?;
    if !response.status().is_success() {
        return Err("service rejected request".into());
    }
    let bytes = response.bytes().await?;
    Ok(if bytes.is_empty() {
        Value::Null
    } else {
        serde_json::from_slice(&bytes)?
    })
}
pub fn credential(name: &str) -> Result<String> {
    let root = PathBuf::from(
        std::env::var_os("CREDENTIALS_DIRECTORY").ok_or("missing credentials directory")?,
    );
    Ok(std::fs::read_to_string(root.join(name))?.trim().to_owned())
}
pub fn field<'a>(value: &'a Value, name: &str) -> Result<&'a str> {
    value
        .get(name)
        .and_then(Value::as_str)
        .ok_or_else(|| format!("missing service field: {name}").into())
}
pub fn finish(result: Result<()>, message: &str) -> std::process::ExitCode {
    match result {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(_) => {
            eprintln!("{message}");
            std::process::ExitCode::FAILURE
        }
    }
}
