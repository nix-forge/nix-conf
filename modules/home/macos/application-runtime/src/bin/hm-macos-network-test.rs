//! Two-minute LAN acceptance from the canonical application's command runner.
use clap::Parser;
use macos_application_tools::{Result, fail, run};
use serde_json::{Value, json};
use std::{
    collections::HashSet,
    io::{self, Write},
    net::{IpAddr, SocketAddr, TcpStream, ToSocketAddrs},
    path::PathBuf,
    time::{Duration, Instant},
};
#[derive(Parser)]
struct Args {
    #[arg(long)]
    app: PathBuf,
    #[arg(long)]
    lifecycle: String,
    #[arg(long)]
    probe: String,
    #[arg(long, required = true)]
    endpoint: Vec<String>,
}
async fn ancestry(app: &std::path::Path) -> Result<Vec<Value>> {
    let mut parents = vec![];
    let mut pid = std::process::id();
    let expected = app.join("Contents/MacOS/ChatGPT");
    for _ in 0..32 {
        let result = run("/bin/ps", &["-p", &pid.to_string(), "-o", "ppid=,comm="]).await?;
        if !result.status.success() {
            break;
        }
        let output = String::from_utf8(result.stdout)?;
        let output = output.trim();
        let Some(index) = output.find(char::is_whitespace) else {
            break;
        };
        let (parent, executable) = output.split_at(index);
        let executable = executable.trim_start();
        parents.push(json!({"pid":pid,"executable":executable}));
        if std::path::Path::new(executable) == expected {
            return Ok(parents);
        }
        pid = parent.parse()?;
        if pid <= 1 {
            break;
        }
    }
    fail(
        "Run this acceptance command inside the canonical ChatGPT GUI command runner; SSH/Terminal probes cannot validate its permission",
    )
}
// Match Python ipaddress.is_private (non-globally-reachable) excluding loopback
// and unspecified addresses; scoped IPv6 addresses retain their interface ID.
fn private(ip: IpAddr) -> bool {
    let networks: &[&str] = match ip {
        IpAddr::V4(_) => &[
            "0.0.0.0/8",
            "10.0.0.0/8",
            "127.0.0.0/8",
            "169.254.0.0/16",
            "172.16.0.0/12",
            "192.0.0.0/24",
            "192.0.0.170/31",
            "192.0.2.0/24",
            "192.168.0.0/16",
            "198.18.0.0/15",
            "198.51.100.0/24",
            "203.0.113.0/24",
            "240.0.0.0/4",
        ],
        IpAddr::V6(_) => &[
            "::/128",
            "::1/128",
            "::ffff:0:0/96",
            "64:ff9b:1::/48",
            "100::/64",
            "2001::/23",
            "2001:db8::/32",
            "2002::/16",
            "3fff::/20",
            "fc00::/7",
            "fe80::/10",
        ],
    };
    // IPv4-mapped addresses inherit IPv4 reachability.
    if let IpAddr::V6(ip) = ip
        && let Some(mapped) = ip.to_ipv4_mapped()
    {
        return private(IpAddr::V4(mapped));
    }
    let exceptions: &[&str] = match ip {
        IpAddr::V4(_) => &["192.0.0.9/32", "192.0.0.10/32"],
        IpAddr::V6(_) => &[
            "2001:1::1/128",
            "2001:1::2/128",
            "2001:3::/32",
            "2001:4:112::/48",
            "2001:20::/28",
            "2001:30::/28",
        ],
    };
    let contains = |network: &&str| {
        network
            .parse::<ipnet::IpNet>()
            .is_ok_and(|network| network.contains(&ip))
    };
    networks.iter().any(contains) && !exceptions.iter().any(contains)
}
fn endpoints(specifications: &[String]) -> Result<Vec<(String, SocketAddr)>> {
    let mut seen = HashSet::new();
    let mut result = vec![];
    for endpoint in specifications {
        let (host, port) = endpoint.rsplit_once(':').ok_or("Invalid endpoint")?;
        let port = port.parse::<u16>()?;
        if host.is_empty() || port == 0 {
            return fail("Invalid endpoint");
        }
        for address in (host, port).to_socket_addrs()? {
            let ip = address.ip();
            if !private(ip) || ip.is_loopback() || ip.is_unspecified() {
                return fail(
                    "Acceptance endpoints must resolve to LAN addresses; loopback cannot prove permission",
                );
            }
            let item = (host.to_owned(), address);
            if seen.insert(item.clone()) {
                result.push(item);
            }
        }
    }
    if result.is_empty() {
        return fail("No reachable LAN address was resolved");
    }
    Ok(result)
}
fn emit(value: Value) -> Result<()> {
    println!("{}", serde_json::to_string(&value)?);
    io::stdout().flush()?;
    Ok(())
}
fn numeric(address: SocketAddr) -> String {
    match address {
        SocketAddr::V4(a) => a.ip().to_string(),
        SocketAddr::V6(a) => {
            if a.scope_id() == 0 {
                a.ip().to_string()
            } else {
                format!("{}%{}", a.ip(), a.scope_id())
            }
        }
    }
}
async fn acceptance(args: Args) -> Result<i32> {
    let parents = ancestry(&args.app).await?;
    let endpoints = endpoints(&args.endpoint)?;
    let initial = run(&args.lifecycle, &["--mode", "check"]).await?;
    if !initial.status.success() {
        return fail(&String::from_utf8_lossy(&initial.stderr));
    }
    let app = args.app.to_str().ok_or("Invalid app path")?;
    let signature = run("/usr/bin/codesign", &["-d", "--verbose=4", app])
        .await?
        .stderr;
    emit(json!({"origin":"canonical-gui-ancestor","pid":std::process::id(),"parents":parents}))?;
    let start = Instant::now();
    let mut passed = true;
    for number in 0..5 {
        tokio::time::sleep_until(tokio::time::Instant::from_std(
            start + Duration::from_secs(number * 30),
        ))
        .await;
        let mut results = vec![];
        for (label, address) in &endpoints {
            // A bounded blocking socket connect matches the native TCP check; no state polling.
            let tcp = TcpStream::connect_timeout(address, Duration::from_secs(5));
            let tcp_error = tcp
                .as_ref()
                .err()
                .map(|e| json!({"errno":e.raw_os_error(),"message":e.to_string()}));
            let host = numeric(*address);
            let framework = run(&args.probe, &[&host, &address.port().to_string()]).await?;
            results.push(json!({"endpoint":format!("{label}:{}",address.port()),"address":host,"tcp":tcp.is_ok(),"tcpError":tcp_error,"networkFramework":framework.status.success(),"detail":String::from_utf8_lossy(&framework.stdout).trim()}));
        }
        passed = passed
            && results
                .iter()
                .all(|r| r["tcp"] == true && r["networkFramework"] == true);
        emit(
            json!({"round":number+1,"elapsed":(start.elapsed().as_secs_f64()*100.0).round()/100.0,"results":results}),
        )?;
    }
    let final_check = run(&args.lifecycle, &["--mode", "check"]).await?;
    let same = initial.stdout == final_check.stdout
        && signature
            == run("/usr/bin/codesign", &["-d", "--verbose=4", app])
                .await?
                .stderr;
    ancestry(&args.app).await?;
    passed = passed && final_check.status.success() && same;
    emit(
        json!({"status":if passed{"passed"}else{"failed"},"identityStable":same,"authorization":"unknown"}),
    )?;
    Ok(if passed { 0 } else { 1 })
}
#[tokio::main(flavor = "current_thread")]
async fn main() {
    let code = match acceptance(Args::parse()).await {
        Ok(code) => code,
        Err(error) => {
            eprintln!("{error}");
            1
        }
    };
    std::process::exit(code);
}
