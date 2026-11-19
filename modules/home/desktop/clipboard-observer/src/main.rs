//! Subscribe before snapshot; wipe only for the current user's logind sessions.
use futures_util::StreamExt;
use std::{collections::HashMap, error::Error, time::Duration};
use zbus::{Connection, MatchRule, Message, MessageStream, OwnedObjectPath, OwnedVariant, Proxy};
type Result<T> = std::result::Result<T, Box<dyn Error>>;
const LOGIN: &str = "org.freedesktop.login1";
const ROOT: &str = "/org/freedesktop/login1";
const SESSION: &str = "org.freedesktop.login1.Session";
const PROPERTIES: &str = "org.freedesktop.DBus.Properties";
async fn inspect(
    connection: &Connection,
    owner: &str,
    path: &str,
    requested: bool,
    cliphist: &std::ffi::OsStr,
) -> Result<()> {
    let proxy = Proxy::new(connection, owner, path, PROPERTIES).await?;
    let response = tokio::time::timeout(
        Duration::from_secs(10),
        proxy.call_method("GetAll", &(SESSION,)),
    )
    .await?;
    let response = match response {
        Ok(value) => value,
        Err(zbus::Error::MethodError(name, _, _))
            if [
                "org.freedesktop.login1.NoSuchSession",
                "org.freedesktop.DBus.Error.UnknownObject",
            ]
            .contains(&name.as_str()) =>
        {
            return Ok(());
        }
        Err(error) => return Err(error.into()),
    };
    let mut properties: HashMap<String, OwnedVariant> = response.body().deserialize()?;
    let user = properties.remove("User").ok_or("session user missing")?;
    let (uid, _path): (u32, OwnedObjectPath) = user.try_into()?;
    if uid != rustix::process::getuid().as_raw() {
        return Ok(());
    }
    let locked = bool::try_from(
        properties
            .remove("LockedHint")
            .ok_or("session lock hint missing")?,
    )?;
    if requested || locked {
        let output = nix_conf_process::run_with_grace(
            tokio::process::Command::new(cliphist).arg("wipe"),
            None,
            Duration::from_secs(10),
            Duration::from_secs(2),
        )
        .await?;
        if !output.status.success() {
            return Err("clipboard history wipe failed".into());
        }
    }
    Ok(())
}
fn lock_event(message: &Message) -> Result<Option<(String, bool)>> {
    let header = message.header();
    let interface = header.interface().map(|s| s.as_str()).unwrap_or("");
    let member = header.member().map(|s| s.as_str()).unwrap_or("");
    let path = header.path().map(|s| s.as_str()).unwrap_or("");
    if interface == SESSION && member == "Lock" {
        return Ok(Some((path.to_owned(), true)));
    }
    if interface == PROPERTIES && member == "PropertiesChanged" {
        let (interface, changed, _): (String, HashMap<String, OwnedVariant>, Vec<String>) =
            message.body().deserialize()?;
        if interface == SESSION
            && changed
                .get("LockedHint")
                .is_some_and(|v| bool::try_from(v).unwrap_or(false))
        {
            return Ok(Some((path.to_owned(), true)));
        }
    }
    if interface == "org.freedesktop.login1.Manager" && member == "SessionNew" {
        let (_, path): (String, OwnedObjectPath) = message.body().deserialize()?;
        return Ok(Some((path.to_string(), false)));
    }
    Ok(None)
}
async fn run() -> Result<()> {
    let args: Vec<_> = std::env::args_os().skip(1).collect();
    let [cliphist] = args.as_slice() else {
        return Err("cliphist executable required".into());
    };
    let connection = Connection::system().await?;
    let dbus = zbus::fdo::DBusProxy::new(&connection).await?;
    // A bus-owner change invalidates all queued sender identities. Subscribe
    // before querying owner and taking snapshots; reconnect through systemd.
    let mut owners = tokio::time::timeout(
        Duration::from_secs(10),
        dbus.receive_name_owner_changed_with_args(&[(0, LOGIN)]),
    )
    .await??;
    let owner = tokio::time::timeout(
        Duration::from_secs(10),
        dbus.get_name_owner(zbus::names::BusName::try_from(LOGIN)?),
    )
    .await??;
    let rule = MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .sender(owner.as_str())
        .path_namespace(ROOT)
        .build()?;
    let mut events = tokio::time::timeout(
        Duration::from_secs(10),
        MessageStream::for_match_rule(rule, &connection, std::num::NonZeroUsize::new(1024)),
    )
    .await??;
    let manager = Proxy::new(
        &connection,
        owner.as_str(),
        ROOT,
        "org.freedesktop.login1.Manager",
    )
    .await?;
    let snapshot = tokio::time::timeout(
        Duration::from_secs(10),
        manager.call_method("ListSessions", &()),
    )
    .await??;
    let sessions: Vec<(String, u32, String, String, OwnedObjectPath)> =
        snapshot.body().deserialize()?;
    for (_, uid, _, _, path) in sessions {
        if uid == rustix::process::getuid().as_raw() {
            inspect(&connection, owner.as_str(), path.as_str(), false, cliphist).await?;
        }
    }
    loop {
        tokio::select! {
            event=owners.next()=>{
                let event=event.ok_or("logind owner stream disconnected")?;
                if event.args()?.name().as_str()==LOGIN{return Err("logind owner changed; reconnecting for a new snapshot".into());}
            },
            message=events.next()=>{
                let message=message.ok_or("logind notification bus disconnected")??;
                if message.header().sender().map(|s|s.as_str())!=Some(owner.as_str()){continue;}
                if let Some((path,requested))=lock_event(&message)?{inspect(&connection,owner.as_str(),&path,requested,cliphist).await?;}
            }
        }
    }
}
#[tokio::main(flavor = "current_thread")]
async fn main() -> std::process::ExitCode {
    match run().await {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(_) => {
            eprintln!("Clipboard lock observer failed; reconnecting through its service manager");
            std::process::ExitCode::FAILURE
        }
    }
}
