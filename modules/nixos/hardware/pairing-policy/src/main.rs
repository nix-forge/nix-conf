//! Apply boot-time adapter policy after BlueZ publishes each adapter.
use futures_util::StreamExt;
use std::{
    collections::{HashMap, HashSet},
    error::Error,
    time::Duration,
};
use zbus::{Connection, OwnedObjectPath, OwnedVariant, Proxy, Variant};
type Result<T> = std::result::Result<T, Box<dyn Error>>;
type Interfaces = HashMap<String, HashMap<String, OwnedVariant>>;
const ADAPTER: &str = "org.bluez.Adapter1";
async fn apply(connection: &Connection, owner: &str, path: &str) -> Result<()> {
    let properties = Proxy::new(connection, owner, path, "org.freedesktop.DBus.Properties").await?;
    properties
        .call_method("Set", &(ADAPTER, "Pairable", Variant::from(false)))
        .await?;
    Ok(())
}
async fn disable(adapters: Vec<String>) -> Result<()> {
    if adapters.is_empty() {
        return Ok(());
    }
    let connection = Connection::system().await?;
    let dbus = zbus::fdo::DBusProxy::new(&connection).await?;
    let owner = dbus
        .get_name_owner(zbus::names::BusName::try_from("org.bluez")?)
        .await?;
    let manager = Proxy::new(
        &connection,
        owner.as_str(),
        "/",
        "org.freedesktop.DBus.ObjectManager",
    )
    .await?;
    // receive_signal awaits AddMatch acknowledgement before the snapshot.
    let mut added = manager.receive_signal("InterfacesAdded").await?;
    let snapshot: HashMap<OwnedObjectPath, Interfaces> = manager
        .call_method("GetManagedObjects", &())
        .await?
        .body()
        .deserialize()?;
    let mut pending: HashSet<String> = adapters
        .into_iter()
        .map(|s| format!("/org/bluez/{s}"))
        .collect();
    for (path, interfaces) in snapshot {
        if interfaces.contains_key(ADAPTER) && pending.remove(path.as_str()) {
            apply(&connection, owner.as_str(), path.as_str()).await?;
        }
    }
    while !pending.is_empty() {
        let signal = added
            .next()
            .await
            .ok_or("BlueZ notification stream disconnected")?;
        let (path, interfaces): (OwnedObjectPath, Interfaces) = signal.body().deserialize()?;
        if interfaces.contains_key(ADAPTER) && pending.remove(path.as_str()) {
            apply(&connection, owner.as_str(), path.as_str()).await?;
        }
    }
    Ok(())
}
async fn run() -> Result<()> {
    let mut timeout = 45.0;
    let mut adapters = Vec::new();
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        if arg == "--timeout" {
            timeout = args.next().ok_or("timeout required")?.parse::<f64>()?;
            continue;
        }
        if arg.starts_with('-') {
            return Err("invalid argument".into());
        }
        adapters.push(arg);
    }
    if !timeout.is_finite() || timeout <= 0.0 {
        return Err("positive timeout required".into());
    }
    // Match the former activation wrapper: snapshot boot-time sysfs adapter names.
    for entry in std::fs::read_dir("/sys/class/bluetooth")
        .into_iter()
        .flatten()
    {
        let name = entry?.file_name().to_string_lossy().into_owned();
        if name
            .strip_prefix("hci")
            .is_some_and(|s| !s.is_empty() && s.bytes().all(|b| b.is_ascii_digit()))
        {
            adapters.push(name);
        }
    }
    for adapter in &adapters {
        if !adapter
            .strip_prefix("hci")
            .is_some_and(|s| !s.is_empty() && s.bytes().all(|b| b.is_ascii_digit()))
        {
            return Err("invalid adapter name".into());
        }
    }
    tokio::time::timeout(Duration::try_from_secs_f64(timeout)?, disable(adapters)).await??;
    Ok(())
}
#[tokio::main(flavor = "current_thread")]
async fn main() -> std::process::ExitCode {
    match run().await {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(_) => {
            eprintln!(
                "Bluetooth adapters did not become ready for pairing policy before the deadline, or BlueZ rejected the operation"
            );
            std::process::ExitCode::FAILURE
        }
    }
}
