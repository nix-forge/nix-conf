//! One systemd-owned sample with bounded transactional history.
use rusqlite::{Connection, OptionalExtension, params};
use serde_json::{Value, json};
use std::{
    env,
    fs::{self, OpenOptions},
    io::{Read, Write},
    os::unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt},
    path::{Path, PathBuf},
    time::{Duration, SystemTime, UNIX_EPOCH},
};
type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
fn number(v: &Value) -> f64 {
    v.as_f64().unwrap_or(0.0)
}
fn integer(v: &Value) -> u64 {
    v.as_u64().unwrap_or(0)
}
fn object() -> Value {
    json!({})
}
fn text(path: impl AsRef<Path>) -> Option<String> {
    fs::read_to_string(path).ok().map(|v| v.trim().to_owned())
}
fn configured<'a>(config: &'a Value, key: &str, default: &'a str) -> &'a str {
    config[key].as_str().unwrap_or(default)
}
fn pressure(path: &Path) -> Result<Value> {
    let mut result = object();
    for line in fs::read_to_string(path)?.lines() {
        let mut fields = line.split_whitespace();
        let name = fields.next().ok_or("Missing pressure type")?;
        let values: std::collections::HashMap<_, _> =
            fields.filter_map(|f| f.split_once('=')).collect();
        result[name] = json!(
            values
                .get("avg60")
                .ok_or("Missing average")?
                .parse::<f64>()?
        );
        result[format!("{name}Total")] =
            json!(values.get("total").ok_or("Missing total")?.parse::<u64>()?);
    }
    if result.get("full").is_none() {
        return Err("Missing full pressure".into());
    }
    Ok(result)
}
fn counters(path: &Path) -> Result<Value> {
    let mut result = object();
    for line in text(path).unwrap_or_default().lines() {
        let mut pair = line.split_whitespace();
        let key = pair.next().ok_or("Missing counter")?;
        let value = pair.next().ok_or("Missing count")?.parse::<u64>()?;
        result[key] = json!(value);
    }
    Ok(result)
}
fn group(path: &Path) -> Value {
    ( ||->Result<Value>{let identity=fs::metadata(path)?.ino();let psi=pressure(&path.join("memory.pressure"))?;let stats=counters(&path.join("memory.stat"))?;let mut components=object();for key in ["anon","file","kernel","shmem","slab_reclaimable","slab_unreclaimable"]{if let Some(value)=stats.get(key){components[key]=value.clone();}}let mut limits=object();for key in ["high","max","swap.max"]{limits[key]=json!(text(path.join(format!("memory.{key}"))));}let mut result=json!({"identity":identity,"memory":fs::read_to_string(path.join("memory.current"))?.trim().parse::<u64>()?,"swap":fs::read_to_string(path.join("memory.swap.current"))?.trim().parse::<u64>()?,"pressure":psi["full"],"psi":psi,"components":components,"limits":limits});for key in ["events","events.local","swap.events"]{result[key]=counters(&path.join(format!("memory.{key}")))?;}if fs::metadata(path)?.ino()!=identity{return Ok(Value::Null);}Ok(result)})().unwrap_or(Value::Null)
}
fn delta(current: &Value, previous: &Value) -> Value {
    if current.is_null() || previous.is_null() || current["identity"] != previous["identity"] {
        return object();
    }
    let mut result = object();
    for key in ["events", "events.local", "swap.events"] {
        let Some(new) = current[key].as_object() else {
            return object();
        };
        let Some(old) = previous[key].as_object() else {
            return object();
        };
        if new.keys().ne(old.keys()) || new.iter().any(|(k, v)| integer(v) < integer(&old[k])) {
            return object();
        }
        result[key] = object();
        for (k, v) in new {
            result[key][k] = json!(integer(v) - integer(&old[k]));
        }
    }
    result
}
fn collect(
    config: &Value,
    previous: &Value,
    compatible: bool,
    now: f64,
    boot: &Value,
) -> Result<Value> {
    let codex = group(Path::new(
        config["cgroup"].as_str().ok_or("Missing cgroup")?,
    ));
    let mut groups = object();
    if let Some(observed) = config["observedGroups"].as_object() {
        for (name, path) in observed {
            groups[name] = group(Path::new(path.as_str().ok_or("Invalid group path")?));
        }
    }
    let mut limited = vec![];
    if let Some(patterns) = config["observedPatterns"].as_object() {
        for (name, selector) in patterns {
            let pattern = Path::new(selector["root"].as_str().ok_or("Invalid selector root")?)
                .join(
                    selector["pattern"]
                        .as_str()
                        .ok_or("Invalid selector pattern")?,
                );
            let mut paths = glob::glob(pattern.to_str().ok_or("Invalid path")?)?
                .collect::<std::result::Result<Vec<_>, _>>()?;
            paths.sort();
            if paths.len() > 32 {
                limited.push(name.clone());
            }
            if paths.is_empty() {
                groups[name] = Value::Null;
            }
            if let Some(old) = previous["groups"].as_object() {
                for (key, value) in old {
                    if !value.is_null() && key.starts_with(&format!("{name}/")) {
                        groups[key] = Value::Null;
                    }
                }
            }
            for path in paths.iter().take(32) {
                let key = format!(
                    "{name}/{}",
                    path.file_name()
                        .ok_or("Missing group name")?
                        .to_string_lossy()
                );
                groups[key] = group(path);
            }
        }
    }
    let psi = pressure(Path::new(
        config["systemPressure"]
            .as_str()
            .ok_or("Missing pressure path")?,
    ))?;
    let mut deltas = object();
    deltas["codex"] = if compatible {
        delta(&codex, &previous["codex"])
    } else {
        object()
    };
    if let Some(groups) = groups.as_object() {
        for (name, value) in groups {
            deltas[name] = if compatible {
                delta(value, &previous["groups"][name])
            } else {
                object()
            };
        }
    }
    let available = text(configured(config, "meminfo", "/proc/meminfo")).and_then(|s| {
        s.lines()
            .find(|l| l.starts_with("MemAvailable:"))
            .and_then(|l| l.split_whitespace().nth(1))
            .and_then(|v| v.parse::<u64>().ok())
            .map(|v| v * 1024)
    });
    let mut paging = counters(Path::new(configured(config, "vmstat", "/proc/vmstat")))?;
    paging
        .as_object_mut()
        .ok_or("Invalid paging")?
        .retain(|k, _| ["pswpin", "pswpout", "pgmajfault"].contains(&k.as_str()));
    let old = &previous["paging"]["counters"];
    let elapsed = now - number(&previous["time"]);
    let mut rates = Value::Null;
    if compatible
        && elapsed > 0.0
        && paging
            .as_object()
            .zip(old.as_object())
            .is_some_and(|(new, old)| {
                new.keys().eq(old.keys()) && new.iter().all(|(k, v)| integer(v) >= integer(&old[k]))
            })
    {
        rates = object();
        for (k, v) in paging.as_object().ok_or("Invalid paging")? {
            rates[k] = json!((number(v) - number(&old[k])) / elapsed);
        }
    }
    let zram = text(configured(config, "zramStat", "/sys/block/zram0/mm_stat"))
        .and_then(|s| {
            s.split_whitespace()
                .take(3)
                .map(str::parse::<u64>)
                .collect::<std::result::Result<Vec<_>, _>>()
                .ok()
        })
        .filter(|v| v.len() == 3)
        .map(|v| json!({"originalBytes":v[0],"compressedBytes":v[1],"allocatedBytes":v[2]}));
    Ok(
        json!({"codex":codex,"groups":groups,"discoveryLimited":limited,"eventDeltas":deltas,"systemPressure":psi["full"],"systemPsi":psi,"availableMemory":available,"notifications":[],"time":now,"boot":boot,"paging":{"counters":paging,"perSecond":rates,"pageBytes":rustix::param::page_size()},"zram":zram}),
    )
}
fn add(row: &mut Value, key: &str, amount: f64) {
    row[key] = json!(number(&row[key]) + amount);
}
fn peak(row: &mut Value, key: &str, value: &Value) {
    row[key] = json!(number(&row[key]).max(number(value)));
}
fn stalls(row: &mut Value, psi: &Value, old: &Value, elapsed: f64, valid: bool) {
    if valid && elapsed > 0.0 {
        for key in ["some", "full"] {
            let delta = number(&psi[format!("{key}Total")]) - number(&old[format!("{key}Total")]);
            if delta >= 0.0 {
                add(row, &format!("{key}Microseconds"), delta);
                add(row, &format!("{key}ObservedSeconds"), elapsed);
            }
        }
    }
}
fn summary(
    sample: &Value,
    previous: &Value,
    compatible: bool,
    mut current: Value,
) -> Result<Value> {
    let now = number(&sample["time"]);
    if current.get("last").is_some_and(|v| number(v) > now) {
        current = object();
    }
    add(&mut current, "samples", 1.0);
    if current.get("first").is_none() {
        current["first"] = json!(now);
    }
    current["last"] = json!(now);
    peak(&mut current, "hostFullMax", &sample["systemPressure"]);
    if !sample["availableMemory"].is_null() {
        current["availableMin"] = json!(
            current
                .get("availableMin")
                .map_or(number(&sample["availableMemory"]), |v| number(v)
                    .min(number(&sample["availableMemory"])))
        );
    }
    add(
        &mut current,
        "baselineSamples",
        if compatible { 0.0 } else { 1.0 },
    );
    let elapsed = now - previous.get("time").map_or(now, number);
    stalls(
        &mut current,
        &sample["systemPsi"],
        &previous["systemPsi"],
        elapsed,
        compatible,
    );
    if let Some(zram) = sample["zram"].as_object() {
        for (k, v) in zram {
            peak(&mut current, &format!("{k}Max"), v);
        }
    }
    if compatible
        && elapsed > 0.0
        && let Some(rates) = sample["paging"]["perSecond"].as_object()
    {
        for (k, v) in rates {
            add(&mut current, &format!("{k}Delta"), number(v) * elapsed);
        }
    }
    if current.get("groups").is_none() {
        current["groups"] = object();
    }
    let mut groups = sample["groups"]
        .as_object()
        .cloned()
        .ok_or("Invalid groups")?;
    groups.insert("codex".into(), sample["codex"].clone());
    for (name, group) in groups {
        if current["groups"].get(&name).is_none() {
            current["groups"][&name] = json!({"present":0,"missing":0});
        }
        let row = &mut current["groups"][&name];
        if group.is_null() {
            add(row, "missing", 1.0);
            continue;
        }
        add(row, "present", 1.0);
        if row["identity"] != group["identity"] {
            add(row, "generations", 1.0);
        }
        row["identity"] = group["identity"].clone();
        for k in ["memory", "swap", "pressure"] {
            peak(row, &format!("{k}Max"), &group[k]);
        }
        let old = if name == "codex" {
            &previous["codex"]
        } else {
            &previous["groups"][&name]
        };
        stalls(
            row,
            &group["psi"],
            &old["psi"],
            elapsed,
            compatible && old["identity"] == group["identity"],
        );
        if let Some(events) = sample["eventDeltas"][&name].as_object() {
            for (kind, deltas) in events {
                if row.get(kind).is_none() {
                    row[kind] = object();
                }
                if let Some(deltas) = deltas.as_object() {
                    for (key, value) in deltas {
                        add(&mut row[kind], key, number(value));
                    }
                }
            }
        }
    }
    Ok(current)
}
fn compressed(value: &Value) -> Result<Vec<u8>> {
    let mut encoder = flate2::write::ZlibEncoder::new(Vec::new(), flate2::Compression::default());
    encoder.write_all(&serde_json::to_vec(value)?)?;
    Ok(encoder.finish()?)
}
fn decompressed(bytes: &[u8]) -> Result<Value> {
    let mut decoder = flate2::read::ZlibDecoder::new(bytes);
    let mut bytes = vec![];
    decoder.read_to_end(&mut bytes)?;
    Ok(serde_json::from_slice(&bytes)?)
}
fn private_parent(path: &Path) -> Result<()> {
    let parent = path.parent().ok_or("Missing state parent")?;
    if !parent.exists() {
        fs::create_dir_all(parent)?;
        fs::set_permissions(parent, fs::Permissions::from_mode(0o700))?;
    }
    Ok(())
}
fn history(config: &Value, sample: &Value, previous: &Value, compatible: bool) -> Result<()> {
    let path = Path::new(config["database"].as_str().ok_or("Invalid database path")?);
    private_parent(path)?;
    OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(false)
        .custom_flags(rustix::fs::OFlags::NOFOLLOW.bits() as i32)
        .mode(0o600)
        .open(path)?;
    let maximum = config["historyTotalBytes"]
        .as_u64()
        .unwrap_or(32 * 1024 * 1024);
    if maximum < 256 * 1024 {
        return Err("History allowance too small".into());
    }
    let limit = maximum / (2 * 4096) * 15 / 16;
    let mut db = Connection::open(path)?;
    db.busy_timeout(Duration::from_secs(1))?;
    db.execute_batch(
        "PRAGMA journal_mode=DELETE; PRAGMA temp_store=MEMORY; PRAGMA page_size=4096;",
    )?;
    let actual: i64 = db.query_row(&format!("PRAGMA max_page_count={limit}"), [], |r| r.get(0))?;
    let actual = u64::try_from(actual)?;
    if actual > limit {
        return Err("Existing history exceeds allowance".into());
    }
    db.execute_batch("CREATE TABLE IF NOT EXISTS raw(time REAL PRIMARY KEY,data BLOB NOT NULL); CREATE TABLE IF NOT EXISTS summary(time INTEGER PRIMARY KEY,data BLOB NOT NULL);")?;
    let now = number(&sample["time"]);
    let bucket = (now / 300.0).floor() as i64 * 300;
    {
        let tx = db.transaction()?;
        tx.execute(
            "DELETE FROM raw WHERE time < ? OR time > ?",
            params![now - config["rawSeconds"].as_f64().unwrap_or(86400.0), now],
        )?;
        tx.execute(
            "DELETE FROM summary WHERE time < ? OR time > ?",
            params![
                now - config["summarySeconds"].as_f64().unwrap_or(14.0 * 86400.0),
                bucket
            ],
        )?;
        tx.commit()?;
    }
    for _ in 0..128 {
        let result = (|| -> Result<()> {
            let tx = db.transaction()?;
            let row: Option<Vec<u8>> = tx
                .query_row("SELECT data FROM summary WHERE time=?", [bucket], |r| {
                    r.get(0)
                })
                .optional()?;
            let aggregate = summary(
                sample,
                previous,
                compatible,
                row.map(|v| decompressed(&v))
                    .transpose()?
                    .unwrap_or_else(object),
            )?;
            tx.execute(
                "INSERT OR REPLACE INTO raw VALUES(?,?)",
                params![now, compressed(sample)?],
            )?;
            tx.execute(
                "INSERT OR REPLACE INTO summary VALUES(?,?)",
                params![bucket, compressed(&aggregate)?],
            )?;
            tx.commit()?;
            Ok(())
        })();
        match result {
            Ok(()) => return Ok(()),
            Err(error) => {
                let full=error.downcast_ref::<rusqlite::Error>().is_some_and(|e|matches!(e,rusqlite::Error::SqliteFailure(e,_) if e.code==rusqlite::ErrorCode::DiskFull));
                if !full {
                    return Err(error);
                }
                let raw: bool =
                    db.query_row("SELECT EXISTS(SELECT 1 FROM raw)", [], |r| r.get(0))?;
                let table = if raw { "raw" } else { "summary" };
                let deleted=db.execute(&format!("DELETE FROM {table} WHERE time IN (SELECT time FROM {table} ORDER BY time LIMIT 128)"),[])?;
                if deleted == 0 {
                    return Err(error);
                }
            }
        }
    }
    Err("History cannot retain sample".into())
}
fn save(path: &Path, state: &Value) -> Result<()> {
    private_parent(path)?;
    let mut temporary =
        tempfile::NamedTempFile::new_in(path.parent().ok_or("Missing state directory")?)?;
    temporary.write_all(&serde_json::to_vec(state)?)?;
    temporary.persist(path)?;
    Ok(())
}
fn append_history(path: &Path, sample: &Value, maximum: u64) -> Result<()> {
    let mut record = serde_json::to_vec(sample)?;
    record.push(b'\n');
    if record.len() as u64 > maximum {
        return Err("Diagnostic record too large".into());
    }
    private_parent(path)?;
    if fs::metadata(path).is_ok_and(|m| m.len() + record.len() as u64 > maximum) {
        let mut rotated = path.as_os_str().to_os_string();
        rotated.push(".1");
        fs::rename(path, PathBuf::from(rotated))?;
    }
    OpenOptions::new()
        .append(true)
        .create(true)
        .mode(0o600)
        .custom_flags(rustix::fs::OFlags::NOFOLLOW.bits() as i32)
        .open(path)?
        .write_all(&record)?;
    Ok(())
}
fn run(config: &Value) -> Result<()> {
    let state_path = Path::new(config["state"].as_str().ok_or("Missing state path")?);
    let mut state = fs::read(state_path)
        .ok()
        .and_then(|v| serde_json::from_slice::<Value>(&v).ok())
        .filter(Value::is_object)
        .unwrap_or_else(object);
    let now = SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs_f64();
    let policy = &config["policy"];
    let previous = state.get("sample").cloned().unwrap_or_else(object);
    let boot = json!(text(configured(
        config,
        "bootId",
        "/proc/sys/kernel/random/boot_id"
    )));
    let elapsed = now - previous.get("time").map_or(now, number);
    let compatible = boot == previous["boot"]
        && elapsed >= 0.0
        && elapsed <= number(&policy["maxSampleGapSeconds"]);
    if !compatible {
        for name in ["codex", "system"] {
            if let Some(value) = state.get_mut(name) {
                value["count"] = json!(0);
                if (!boot.is_null() && !previous["boot"].is_null() && boot != previous["boot"])
                    || elapsed < 0.0
                {
                    value["notified"] = json!(0);
                }
            }
        }
    }
    let mut sample = collect(config, &previous, compatible, now, &boot)?;
    if sample["codex"]["identity"] != previous["codex"]["identity"] {
        if state.get("codex").is_none() {
            state["codex"] = object();
        }
        state["codex"]["count"] = json!(0);
    }
    let g = &sample["codex"];
    let codex = !g.is_null()
        && (number(&g["pressure"]) >= number(&policy["pressurePercent"])
            || number(&g["memory"])
                >= number(&policy["memoryMax"]) * number(&policy["nearLimitRatio"])
            || (number(&g["swap"])
                >= number(&policy["swapMax"]) * number(&policy["nearLimitRatio"])
                && number(&g["memory"]) >= number(&policy["memoryHigh"])));
    let mut stalled = Vec::new();
    let mut groups = sample["groups"]
        .as_object()
        .cloned()
        .ok_or("Invalid groups")?;
    groups.insert("codex".into(), g.clone());
    for (name, group) in groups {
        if !group.is_null() && number(&group["pressure"]) >= number(&policy["pressurePercent"]) {
            stalled.push(format!("{name}: {:.1}%", number(&group["pressure"])));
        }
    }
    let context = if stalled.is_empty() {
        String::new()
    } else {
        format!(" Monitored group stalls: {}.", stalled.join(", "))
    };
    let candidates = [
        (
            "system",
            number(&sample["systemPressure"]) >= number(&policy["pressurePercent"]),
            format!(
                "System memory stalls: {:.1}% over the last minute.{context}",
                number(&sample["systemPressure"])
            ),
        ),
        (
            "codex",
            codex,
            format!(
                "Codex: {:.1} GiB RAM, {:.1} GiB swap; memory stalls {:.1}%. Finish unused tool sessions when their work is complete.",
                number(&g["memory"]) / 1073741824.0,
                number(&g["swap"]) / 1073741824.0,
                number(&g["pressure"])
            ),
        ),
    ];
    let mut messages = vec![];
    for (name, active, message) in candidates {
        let count = if active {
            integer(&state[name]["count"]) + 1
        } else {
            0
        };
        let last = number(&state[name]["notified"]);
        let due = count as f64 >= number(&policy["samples"])
            && now - last >= number(&policy["cooldownSeconds"]);
        state[name] = json!({"count":count,"notified":if due{now}else{last}});
        if due {
            messages.push(message);
        }
    }
    sample["notifications"] = json!(messages);
    if config.get("database").is_some() && history(config, &sample, &previous, compatible).is_err()
    {
        sample["historyError"] = json!("HistoryError");
    }
    state["sample"] = sample;
    save(state_path, &state)?;
    if let Some(path) = config["history"].as_str() {
        append_history(
            Path::new(path),
            &state["sample"],
            integer(&config["historyMaxBytes"]),
        )?;
    }
    if !messages.is_empty() {
        let status = std::process::Command::new(
            config["notify"]
                .as_str()
                .ok_or("Missing notification executable")?,
        )
        .args([
            "--app-name=Codex resource monitor",
            "--urgency=normal",
            "--expire-time=12000",
            "Memory pressure",
            &messages.join("\n"),
        ])
        .status()?;
        if !status.success() {
            return Err("Notification failed".into());
        }
    }
    Ok(())
}
fn main_result() -> Result<()> {
    let args: Vec<_> = env::args().skip(1).collect();
    let config: Value = serde_json::from_slice(&fs::read(args.first().ok_or("Expected config")?)?)?;
    if args.len() == 1 {
        return run(&config);
    }
    if args.len() < 3 || args[1] != "--history" || !["raw", "summary"].contains(&args[2].as_str()) {
        return Err("Expected --history raw|summary [--limit N]".into());
    }
    let limit = if args.len() == 5 && args[3] == "--limit" {
        args[4].parse::<i64>()?
    } else if args.len() == 3 {
        20
    } else {
        return Err("Invalid history arguments".into());
    };
    if !(1..=10000).contains(&limit) {
        return Err("History limit must be between 1 and 10000".into());
    }
    let db = Connection::open_with_flags(
        config["database"].as_str().ok_or("Missing database")?,
        rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY,
    )?;
    let table = &args[2];
    let (oldest, newest, count): (Option<f64>, Option<f64>, i64) = db.query_row(
        &format!("SELECT min(time),max(time),count(*) FROM {table}"),
        [],
        |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
    )?;
    let mut statement = db.prepare(&format!(
        "SELECT data FROM {table} ORDER BY time DESC LIMIT ?"
    ))?;
    let rows = statement
        .query_map([limit], |r| r.get::<_, Vec<u8>>(0))?
        .map(|row| decompressed(&row?))
        .collect::<Result<Vec<_>>>()?;
    println!(
        "{}",
        json!({"oldest":oldest,"newest":newest,"count":count,"rows":rows})
    );
    Ok(())
}
fn main() {
    if let Err(error) = main_result() {
        eprintln!("Pressure monitor failed: {error}");
        std::process::exit(1);
    }
}
