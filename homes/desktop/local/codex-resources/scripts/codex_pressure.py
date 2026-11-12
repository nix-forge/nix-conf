"""Sample cgroup pressure and notify only after sustained, actionable pressure."""

from __future__ import annotations

# ruff: file-ignore[subprocess-without-shell-equals-true] -- Only the Nix-generated notify-send command is executed, with an argument list and no shell.
import argparse
import contextlib
import json
import os
import sqlite3
import subprocess  # ruff: ignore[suspicious-subprocess-import] -- Only the generated notify-send executable is invoked.
import tempfile
import time
import zlib
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Mapping


GIB = 1024**3
ZRAM_COUNTERS = ("originalBytes", "compressedBytes", "allocatedBytes")
MAX_HISTORY_ROWS = 10000
MAX_DISCOVERED_GROUPS = 32


def pressure(path: Path) -> dict[str, float | int]:
    """Read both one-minute stall percentages and cumulative microseconds.

    Returns:
        Named stall percentages and cumulative counters.

    Raises:
        ValueError: Full-stall accounting is absent.

    """
    result = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        fields = line.split()
        values = dict(field.split("=", 1) for field in fields[1:])
        result[fields[0]] = float(values["avg60"])
        result[fields[0] + "Total"] = int(values["total"])
    if "full" not in result:
        msg = "Pressure file lacks full-stall accounting"
        raise ValueError(msg)
    return result


def optional_text(path: Path) -> str | None:
    """Read optional diagnostics without losing the other available groups.

    Returns:
        Text, or None for a missing or inaccessible diagnostic.

    """
    try:
        return path.read_text(encoding="utf-8").strip()
    except OSError, ValueError:
        return None


def read_group(path: Path) -> dict | None:
    """Read accounting; an inactive application has no cgroup to inspect.

    Returns:
        Current bytes and pressure, or None if the application is absent.

    """
    try:
        identity = path.stat().st_ino
        psi = pressure(path / "memory.pressure")
        result = {
            "identity": identity,
            "memory": int((path / "memory.current").read_text(encoding="utf-8")),
            "swap": int((path / "memory.swap.current").read_text(encoding="utf-8")),
            "pressure": psi["full"],
            "psi": psi,
            "components": {
                key: int(value)
                for key, value in (
                    line.split()
                    for line in (optional_text(path / "memory.stat") or "").splitlines()
                )
                if key
                in {
                    "anon",
                    "file",
                    "kernel",
                    "shmem",
                    "slab_reclaimable",
                    "slab_unreclaimable",
                }
            },
            "limits": {
                name: optional_text(path / ("memory." + name))
                for name in ("high", "max", "swap.max")
            },
        }
        for name in ("events", "events.local", "swap.events"):
            result[name] = {
                key: int(value)
                for key, value in (
                    line.split()
                    for line in (
                        optional_text(path / ("memory." + name)) or ""
                    ).splitlines()
                )
            }
        # Do not join readings from two generations of a transient group.
        return result if path.stat().st_ino == identity else None
    except OSError, ValueError:
        return None


def event_delta(current: dict | None, previous: dict | None) -> dict:
    """Compare compatible group generations without treating resets as events.

    Returns:
        Separate memory and swap counter deltas, or an empty baseline.

    """
    if not current or not previous or current["identity"] != previous.get("identity"):
        return {}
    result = {}
    for name in ("events", "events.local", "swap.events"):
        old = previous.get(name, {})
        new = current[name]
        if old.keys() != new.keys() or any(new[key] < old[key] for key in new):
            return {}
        result[name] = {key: new[key] - old[key] for key in new}
    return result


def append_history(path: Path, sample: dict, maximum: int) -> None:
    """Append private diagnostics, retaining at most two size-bounded files.

    Raises:
        ValueError: One diagnostic record exceeds the configured file bound.

    """
    record = (json.dumps(sample, separators=(",", ":")) + "\n").encode()
    if len(record) > maximum:
        msg = "Pressure diagnostic record exceeds history limit"
        raise ValueError(msg)
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    if path.exists() and path.stat().st_size + len(record) > maximum:
        path.replace(path.with_name(path.name + ".1"))
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "ab") as stream:
        stream.write(record)


def paging(config: dict, previous: dict, compatible: bool, now: float) -> dict:
    """Record host paging counters and rates, with explicit reset baselines.

    Returns:
        Raw page/fault counters and compatible per-second rates.

    """
    counters = {}
    for line in (
        optional_text(Path(config.get("vmstat", "/proc/vmstat"))) or ""
    ).splitlines():
        key, value = line.split()
        if key in {"pswpin", "pswpout", "pgmajfault"}:
            counters[key] = int(value)
    old = previous.get("paging", {}).get("counters", {})
    elapsed = now - previous.get("time", now)
    valid = compatible and elapsed > 0 and counters.keys() == old.keys()
    valid = valid and all(value >= old[key] for key, value in counters.items())
    return {
        "counters": counters,
        "perSecond": {
            key: (value - old[key]) / elapsed for key, value in counters.items()
        }
        if valid
        else None,
        "pageBytes": os.sysconf("SC_PAGE_SIZE"),
    }


def zram(config: dict) -> dict | None:
    """Separate logical swapped data from physical compressed allocation.

    Returns:
        Named byte counters, or None when unavailable.

    """
    fields = (
        optional_text(Path(config.get("zramStat", "/sys/block/zram0/mm_stat"))) or ""
    ).split()
    if len(fields) < len(ZRAM_COUNTERS):
        return None
    return dict(
        zip(
            ZRAM_COUNTERS,
            map(int, fields[:3]),
            strict=True,
        )
    )


def summarize_host(
    sample: dict, previous: dict, compatible: bool, current: dict
) -> None:
    """Accumulate compatible host stalls/paging and physical zram peaks."""
    elapsed = sample["time"] - previous.get("time", sample["time"])
    if compatible and elapsed > 0:
        for key in ("some", "full"):
            delta = sample.get("systemPsi", {}).get(key + "Total", 0) - previous.get(
                "systemPsi", {}
            ).get(key + "Total", 0)
            if delta >= 0:
                current[key + "Microseconds"] = (
                    current.get(key + "Microseconds", 0) + delta
                )
                current[key + "ObservedSeconds"] = (
                    current.get(key + "ObservedSeconds", 0) + elapsed
                )
    for key, value in (sample.get("zram") or {}).items():
        current[key + "Max"] = max(current.get(key + "Max", 0), value)
    rates = sample.get("paging", {}).get("perSecond")
    if rates and compatible and elapsed > 0:
        for key, rate in rates.items():
            current[key + "Delta"] = current.get(key + "Delta", 0) + rate * elapsed


def summary(sample: dict, previous: dict, compatible: bool, current: dict) -> dict:  # ruff: ignore[complex-structure] -- Independent counters and missing-group baselines stay in one summary pass.
    """Keep peaks, missing counts and compatible deltas, never averaged counters.

    Returns:
        Updated five-minute summary with independent group deltas.

    """
    if current.get("last", sample["time"]) > sample["time"]:
        current = {}
    current.setdefault("samples", 0)
    current["samples"] += 1
    current.setdefault("first", sample["time"])
    current["last"] = sample["time"]
    current["hostFullMax"] = max(
        current.get("hostFullMax", 0), sample["systemPressure"]
    )
    available = sample.get("availableMemory")
    if available is not None:
        current["availableMin"] = min(current.get("availableMin", available), available)
    current["baselineSamples"] = current.get("baselineSamples", 0) + int(not compatible)
    summarize_host(sample, previous, compatible, current)
    groups = current.setdefault("groups", {})
    observed = {"codex": sample["codex"], **sample["groups"]}
    old_groups = {"codex": previous.get("codex"), **previous.get("groups", {})}
    for name, group in observed.items():
        row = groups.setdefault(name, {"present": 0, "missing": 0})
        if group is None:
            row["missing"] += 1
            continue
        row["present"] += 1
        if row.get("identity") != group["identity"]:
            row["generations"] = row.get("generations", 0) + 1
        row["identity"] = group["identity"]
        for key in ("memory", "swap", "pressure"):
            row[key + "Max"] = max(row.get(key + "Max", 0), group[key])
        old = old_groups.get(name) or {}
        valid = compatible and old.get("identity") == group["identity"]
        elapsed = sample["time"] - previous.get("time", sample["time"])
        for key in ("some", "full"):
            delta = group["psi"].get(key + "Total", 0) - old.get("psi", {}).get(
                key + "Total", 0
            )
            if valid and elapsed > 0 and delta >= 0:
                row[key + "Microseconds"] = row.get(key + "Microseconds", 0) + delta
                row[key + "ObservedSeconds"] = (
                    row.get(key + "ObservedSeconds", 0) + elapsed
                )
        for kind, deltas in sample["eventDeltas"].get(name, {}).items():
            totals = row.setdefault(kind, {})
            for key, value in deltas.items():
                totals[key] = totals.get(key, 0) + value
    return current


def retain_history(
    config: dict, sample: dict, previous: dict, compatible: bool
) -> None:
    """Keep age- and size-bounded transactional history with five-minute peaks.

    Half the total allowance bounds the database; the other half accommodates
    its rollback journal. No WAL or on-disk temporary sorting is used. Capacity
    eviction shortens coverage explicitly instead of promising a fixed duration.

    Raises:
        ValueError: The configured allowance or sample cannot be retained.
        sqlite3.OperationalError: Database storage is unavailable or full.

    """
    path = Path(config["database"])
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    os.close(fd)
    maximum = config.get("historyTotalBytes", 32 * 1024 * 1024)
    page_size = 4096
    if maximum < 256 * 1024:
        message = "History needs at least 256 KiB including rollback space"
        raise ValueError(message)
    with contextlib.closing(sqlite3.connect(path, timeout=1)) as db:
        db.execute("PRAGMA journal_mode=DELETE")
        db.execute("PRAGMA temp_store=MEMORY")
        db.execute("PRAGMA page_size=4096")
        limit = maximum // (2 * page_size) * 15 // 16
        actual = db.execute(f"PRAGMA max_page_count={limit}").fetchone()[0]
        if actual > limit:
            message = "Existing history exceeds the configured database allowance"
            raise ValueError(message)
        db.execute(
            "CREATE TABLE IF NOT EXISTS raw (time REAL PRIMARY KEY, data BLOB NOT NULL)"
        )
        db.execute(
            "CREATE TABLE IF NOT EXISTS summary (time INTEGER PRIMARY KEY, data BLOB NOT NULL)"
        )
        now = sample["time"]
        # Remove future data after a backward wall-clock step as well as expired
        # rows. Boot and cgroup changes are separately baseline-safe.
        db.execute(
            "DELETE FROM raw WHERE time < ? OR time > ?",
            (now - config.get("rawSeconds", 86400), now),
        )
        bucket = int(now // 300) * 300
        db.execute(
            "DELETE FROM summary WHERE time < ? OR time > ?",
            (now - config.get("summarySeconds", 14 * 86400), bucket),
        )
        db.commit()
        # Bound work even for a damaged/oversized sample. A full transaction
        # rolls back; eviction is committed before retrying the single sample.
        for _ in range(128):
            try:
                row = db.execute(
                    "SELECT data FROM summary WHERE time = ?", (bucket,)
                ).fetchone()
                aggregate = summary(
                    sample,
                    previous,
                    compatible,
                    json.loads(zlib.decompress(row[0])) if row else {},
                )
                db.execute(
                    "INSERT OR REPLACE INTO raw VALUES (?, ?)",
                    (
                        now,
                        zlib.compress(
                            json.dumps(sample, separators=(",", ":")).encode()
                        ),
                    ),
                )
                db.execute(
                    "INSERT OR REPLACE INTO summary VALUES (?, ?)",
                    (
                        bucket,
                        zlib.compress(
                            json.dumps(aggregate, separators=(",", ":")).encode()
                        ),
                    ),
                )
                db.commit()
            except sqlite3.OperationalError as error:
                db.rollback()
                if "full" not in str(error).lower():
                    raise
                # Prefer losing old raw detail before long-term summaries.
                table = (
                    "raw"
                    if db.execute("SELECT 1 FROM raw LIMIT 1").fetchone()
                    else "summary"
                )
                deleted = db.execute(
                    f"DELETE FROM {table} WHERE time IN (SELECT time FROM {table} ORDER BY time LIMIT 128)"  # ruff: ignore[hardcoded-sql-expression] -- table is selected exclusively from two literals.
                ).rowcount
                db.commit()
                if not deleted:
                    raise
            else:
                return
        message = "History capacity cannot retain this sample"
        raise ValueError(message)


def warning(
    sample: Mapping[str, float | int], policy: Mapping[str, float | int]
) -> bool:
    """Identify pressure or near-exhaustion; cold swap occupancy alone is quiet.

    Returns:
        Whether this sample warrants counting toward a notification.

    """
    return (
        sample["pressure"] >= policy["pressurePercent"]
        or sample["memory"] >= policy["memoryMax"] * policy["nearLimitRatio"]
        or (
            sample["swap"] >= policy["swapMax"] * policy["nearLimitRatio"]
            and sample["memory"] >= policy["memoryHigh"]
        )
    )


def advance(
    previous: dict,
    active: bool,
    now: float,
    policy: Mapping[str, float | int],
) -> tuple[dict, bool]:
    """Debounce consecutive samples and rate-limit each independent warning.

    Returns:
        Updated state and whether a notification is due.

    """
    count = previous.get("count", 0) + 1 if active else 0
    last = previous.get("notified", 0)
    due = count >= policy["samples"] and now - last >= policy["cooldownSeconds"]
    return {"count": count, "notified": now if due else last}, due


def save(path: Path, state: dict) -> None:
    """Atomically replace private state without following an existing file link."""
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(state, stream)
        Path(temporary).replace(path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def collect(config: dict, previous: dict, compatible: bool) -> dict:
    """Collect independent named groups without summing hierarchical counters.

    Returns:
        One diagnostic snapshot and compatible event deltas.

    """
    group = read_group(Path(config["cgroup"]))
    groups = {
        name: read_group(Path(path))
        for name, path in config.get("observedGroups", {}).items()
    }
    limited = []
    for name, selector in config.get("observedPatterns", {}).items():
        paths = sorted(Path(selector["root"]).glob(selector["pattern"]))
        if len(paths) > MAX_DISCOVERED_GROUPS:
            limited.append(name)
        if not paths:
            groups[name] = None
        for old_name, old_group in previous.get("groups", {}).items():
            if old_group is not None and old_name.startswith(name + "/"):
                groups[old_name] = None
        for path in paths[:MAX_DISCOVERED_GROUPS]:
            groups[name + "/" + path.name] = read_group(path)
    psi = pressure(Path(config["systemPressure"]))
    system_pressure = psi["full"]
    observed = {"codex": group, **groups}
    old_groups = {"codex": previous.get("codex"), **previous.get("groups", {})}
    deltas = {
        name: event_delta(sample, old_groups.get(name)) if compatible else {}
        for name, sample in observed.items()
    }
    meminfo = optional_text(Path(config.get("meminfo", "/proc/meminfo"))) or ""
    available = next(
        (
            int(line.split()[1]) * 1024
            for line in meminfo.splitlines()
            if line.startswith("MemAvailable:")
        ),
        None,
    )
    return {
        "codex": group,
        "groups": groups,
        "discoveryLimited": limited,
        "eventDeltas": deltas,
        "systemPressure": system_pressure,
        "systemPsi": psi,
        "availableMemory": available,
        "notifications": [],
    }


def stall_context(sample: dict, threshold: float) -> str:
    """Label simultaneously stalled groups without asserting causation.

    Returns:
        Additional warning context, or an empty string.

    """
    stalled = [
        f"{name}: {group['pressure']:.1f}%"
        for name, group in {"codex": sample["codex"], **sample["groups"]}.items()
        if group is not None and group["pressure"] >= threshold
    ]
    return " Monitored group stalls: " + ", ".join(stalled) + "." if stalled else ""


def reset_baselines(
    state: dict, boot: str | None, now: float, compatible: bool
) -> None:
    """Discard debounce/cooldown across a reboot or a backward clock step."""
    previous = state.get("sample", {})
    if not compatible:
        for name in ("codex", "system"):
            if name in state:
                state[name]["count"] = 0
                if (
                    boot is not None
                    and previous.get("boot") is not None
                    and boot != previous["boot"]
                ) or now < previous.get("time", now):
                    state[name]["notified"] = 0


def run(config: dict) -> None:
    """Sample once; systemd owns timing, overlap prevention and cancellation."""
    state_path = Path(config["state"])
    try:
        state = json.loads(state_path.read_text(encoding="utf-8"))
    except FileNotFoundError, ValueError:
        state = {}
    if not isinstance(state, dict):
        state = {}
    now = time.time()
    policy = config["policy"]
    previous = state.get("sample", {})
    boot = optional_text(Path(config.get("bootId", "/proc/sys/kernel/random/boot_id")))
    # Suspend/logout must not turn two isolated readings into sustained pressure.
    compatible = (
        boot == previous.get("boot")
        and 0 <= now - previous.get("time", now) <= policy["maxSampleGapSeconds"]
    )
    reset_baselines(state, boot, now, compatible)
    sample = collect(config, previous, compatible)
    sample.update({"time": now, "boot": boot})
    sample["paging"] = paging(config, previous, compatible, now)
    sample["zram"] = zram(config)
    group = sample["codex"]
    if (group or {}).get("identity") != (previous.get("codex") or {}).get("identity"):
        state.setdefault("codex", {})["count"] = 0
    samples = {
        "system": (
            sample["systemPressure"] >= policy["pressurePercent"],
            f"System memory stalls: {sample['systemPressure']:.1f}% over the last minute."
            + stall_context(sample, policy["pressurePercent"]),
        ),
        "codex": (
            group is not None and warning(group, policy),
            ""
            if group is None
            else f"Codex: {group['memory'] / GIB:.1f} GiB RAM, "
            f"{group['swap'] / GIB:.1f} GiB swap; "
            f"memory stalls {group['pressure']:.1f}%. "
            "Finish unused tool sessions when their work is complete.",
        ),
    }
    messages = []
    for name, (active, message) in samples.items():
        state[name], due = advance(state.get(name, {}), active, now, policy)
        if due:
            messages.append(message)
    sample["notifications"] = messages
    if "database" in config:
        try:
            retain_history(config, sample, previous, compatible)
        except (OSError, ValueError, sqlite3.Error, zlib.error) as error:
            # History failure must not disable current pressure notification.
            sample["historyError"] = type(error).__name__
    state["sample"] = sample
    # Persist before delivery: a failed notification must not create a retry storm.
    save(state_path, state)
    if "history" in config:
        append_history(
            Path(config["history"]), state["sample"], config["historyMaxBytes"]
        )
    if messages:
        subprocess.run(
            [
                config["notify"],
                "--app-name=Codex resource monitor",
                "--urgency=normal",
                "--expire-time=12000",
                "Memory pressure",
                "\n".join(messages),
            ],
            check=True,
            shell=False,
        )


def main() -> None:
    """Read generated configuration and take one bounded service-owned sample."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("config", type=Path)
    parser.add_argument("--history", choices=("raw", "summary"))
    parser.add_argument("--limit", type=int, default=20)
    args = parser.parse_args()
    config = json.loads(args.config.read_text(encoding="utf-8"))
    if args.history:
        if not 1 <= args.limit <= MAX_HISTORY_ROWS:
            parser.error("history limit must be between 1 and 10000")
        path = Path(config["database"]).resolve()
        with contextlib.closing(
            sqlite3.connect(path.as_uri() + "?mode=ro", uri=True)
        ) as db:
            oldest, newest, count = db.execute(
                f"SELECT min(time), max(time), count(*) FROM {args.history}"  # ruff: ignore[hardcoded-sql-expression] -- argparse restricts the table name.
            ).fetchone()
            rows = db.execute(
                f"SELECT data FROM {args.history} ORDER BY time DESC LIMIT ?",  # ruff: ignore[hardcoded-sql-expression] -- argparse restricts the table name.
                (args.limit,),
            ).fetchall()
        print(  # ruff: ignore[print] -- Explicit user-requested read-only history output.
            json.dumps({
                "oldest": oldest,
                "newest": newest,
                "count": count,
                "rows": [json.loads(zlib.decompress(row[0])) for row in rows],
            })
        )
    else:
        run(config)


if __name__ == "__main__":
    main()
