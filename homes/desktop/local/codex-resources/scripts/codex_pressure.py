"""Sample cgroup pressure and notify only after sustained, actionable pressure."""

from __future__ import annotations

# ruff: file-ignore[subprocess-without-shell-equals-true] -- Only the Nix-generated notify-send command is executed, with an argument list and no shell.
import argparse
import json
import os
import subprocess  # ruff: ignore[suspicious-subprocess-import] -- Only the generated notify-send executable is invoked.
import tempfile
import time
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Mapping


GIB = 1024**3


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
    except FileNotFoundError, PermissionError:
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
    except FileNotFoundError, PermissionError:
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
    args = parser.parse_args()
    run(json.loads(args.config.read_text(encoding="utf-8")))


if __name__ == "__main__":
    main()
