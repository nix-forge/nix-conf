use reqwest::{Client, Method};
use serde_json::{Value, json};
use std::{collections::HashSet, env, fs, time::Duration};
type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
struct Dns {
    client: Client,
    api: String,
    token: String,
}
impl Dns {
    async fn request(&self, method: Method, suffix: &str, body: Option<Value>) -> Result<Value> {
        let mut request = self
            .client
            .request(method, format!("{}{}", self.api, suffix))
            .bearer_auth(&self.token);
        if let Some(body) = body {
            request = request.json(&body);
        }
        let response: Value = request.send().await?.error_for_status()?.json().await?;
        if response["success"] != true {
            return Err("DNS API rejected request".into());
        }
        response
            .get("result")
            .cloned()
            .ok_or_else(|| "Invalid DNS response".into())
    }
    async fn records(&self, hostname: &str) -> Result<Vec<Value>> {
        let mut url = reqwest::Url::parse(&self.api)?;
        url.query_pairs_mut()
            .append_pair("name.exact", hostname)
            .append_pair("per_page", "100");
        let response: Value = self
            .client
            .get(url)
            .bearer_auth(&self.token)
            .send()
            .await?
            .error_for_status()?
            .json()
            .await?;
        if response["success"] != true {
            return Err("DNS API rejected request".into());
        }
        let records = response["result"]
            .as_array()
            .ok_or("Invalid DNS response")?;
        if records.len() >= 100 || records.iter().any(|r| !r.is_object()) {
            return Err("Unsafe DNS record list".into());
        }
        Ok(records.clone())
    }
}
fn id(value: &str) -> bool {
    value.len() == 32
        && value
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}
fn label(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 63
        && value
            .bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
        && !value.starts_with('-')
        && !value.ends_with('-')
}
fn matching<'a>(records: &'a [Value], hostname: &str, address: &str) -> Result<Option<&'a Value>> {
    if records.is_empty() {
        return Ok(None);
    }
    if records.len() != 1
        || records[0]["type"] != "A"
        || records[0]["name"] != hostname
        || records[0]["content"] != address
        || records[0]["proxied"] != false
    {
        return Err("Unexpected DNS records; refusing to overwrite".into());
    }
    Ok(records.first())
}
async fn reconcile(args: &[String]) -> Result<()> {
    if args.len() < 3 {
        return Err("Expected DOMAIN ADDRESS SITE [SITE ...]".into());
    }
    let (domain, address, names) = (&args[0], &args[1], &args[2..]);
    if domain.len() > 253 || domain.split('.').count() < 2 || !domain.split('.').all(label) {
        return Err("Invalid HTTPS domain".into());
    }
    let credentials = std::path::PathBuf::from(env::var("CREDENTIALS_DIRECTORY")?);
    let token = fs::read_to_string(credentials.join("cloudflare-token"))?
        .trim()
        .to_owned();
    let zone = fs::read_to_string(credentials.join("cloudflare-zone-id"))?
        .trim()
        .to_owned();
    if !id(&zone) {
        return Err("Invalid zone ID".into());
    }
    let dns = Dns {
        client: Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .timeout(Duration::from_secs(20))
            .build()?,
        api: format!("https://api.cloudflare.com/client/v4/zones/{zone}/dns_records"),
        token,
    };
    let wildcard = format!("*.{domain}");
    let records = dns.records(&wildcard).await?;
    let missing = matching(&records, &wildcard, address)?.is_none();
    let mut seen = HashSet::new();
    let mut remove = Vec::new();
    let mut retained = 0;
    for name in names {
        if !label(name) || !seen.insert(name) {
            return Err("Invalid or duplicate HTTPS site name".into());
        }
        let host = format!("{name}.{domain}");
        let records = dns.records(&host).await?;
        if records
            .iter()
            .any(|r| r["name"] != host || (r["type"] != "A" && r["type"] != "CAA"))
        {
            return Err("Unexpected DNS records; refusing to overwrite".into());
        }
        let addresses: Vec<_> = records
            .iter()
            .filter(|r| r["type"] == "A")
            .cloned()
            .collect();
        if !records.is_empty() && addresses.len() != 1 {
            return Err("Unsafe site DNS records".into());
        }
        if let Some(record) = matching(&addresses, &host, address)? {
            if records.len() > 1 {
                retained += 1;
                continue;
            }
            let key = record["id"].as_str().ok_or("Invalid record ID")?;
            if !id(key) {
                return Err("Invalid record ID".into());
            }
            remove.push(key.to_owned());
        }
    }
    if missing {
        dns.request(
            Method::POST,
            "",
            Some(json!({"type":"A", "name":wildcard,"content":address,"proxied":false,"ttl":1})),
        )
        .await?;
        if matching(&dns.records(&wildcard).await?, &wildcard, address)?.is_none() {
            return Err("Wildcard not visible; keeping exact records".into());
        }
    }
    for key in &remove {
        dns.request(Method::DELETE, &format!("/{key}"), None)
            .await?;
    }
    println!(
        "Wildcard DNS ready; removed {} exact HTTPS records; retained {retained} with CAA policy",
        remove.len()
    );
    Ok(())
}
#[tokio::main(flavor = "current_thread")]
async fn main() {
    if reconcile(&env::args().skip(1).collect::<Vec<_>>())
        .await
        .is_err()
    {
        eprintln!("DNS reconciliation failed; credential and API details suppressed");
        std::process::exit(1);
    }
}
