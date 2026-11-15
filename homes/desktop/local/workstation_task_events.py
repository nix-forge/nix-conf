"""Private scheduler lifecycle records; command arguments and environment are omitted."""

import json
import os
import re
import subprocess  # ruff: ignore[suspicious-subprocess-import] - fixed native resource-query argv
import sys
import time
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from typing import Any


def scope_resources(unit: str) -> dict[str, object]:
    """Read retained native accounting; unavailable counters remain unknown.

    Returns:
        Observed kernel/systemd high-water counters and the unit result.

    """
    try:
        output = subprocess.check_output(  # ruff: ignore[subprocess-without-shell-equals-true] - owning runner supplies its fixed PATH
            [
                os.environ.get("WORKSTATION_SYSTEMCTL", "systemctl"),
                "--user",
                "show",
                unit,
                "-p",
                "MemoryPeak",
                "-p",
                "MemorySwapPeak",
                "-p",
                "ControlGroup",
                "-p",
                "Result",
            ],
            text=True,
            timeout=3,
            stderr=subprocess.DEVNULL,
        )
    except OSError, subprocess.SubprocessError:
        return {"measurement": "unavailable"}
    fields = dict(line.split("=", 1) for line in output.splitlines() if "=" in line)
    result: dict[str, object] = {
        "measurement": "observed-systemd-kernel-high-water",
        "scopeResult": fields.get("Result"),
    }
    for name in ("MemoryPeak", "MemorySwapPeak"):
        value = fields.get(name, "")
        result[name] = (
            int(value) if value.isdigit() and int(value) < 2**64 - 1 else None
        )
    group = fields.get("ControlGroup", "")
    if group.startswith("/") and ".." not in Path(group).parts:
        path = Path("/sys/fs/cgroup") / group.lstrip("/")
        try:
            result["memoryEvents"] = {
                key: int(value)
                for key, value in (
                    line.split()
                    for line in (path / "memory.events")
                    .read_text(encoding="utf-8")
                    .splitlines()
                )
            }
        except OSError:
            result["memoryEvents"] = None
    return result


def write_private(file: Path, record: dict[str, object]) -> None:
    """Replace one bounded private telemetry record atomically."""
    temporary = file.with_suffix(".tmp")
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w") as stream:
        json.dump(record, stream, sort_keys=True)
        stream.write("\n")
    temporary.replace(file)


def host_pressure() -> str | None:
    """Read optional PSI.

    Returns:
        The pressure counters, or unknown when instrumentation is unavailable.

    """
    try:
        return Path("/proc/pressure/memory").read_text(encoding="utf-8")
    except OSError:
        return None


def capacity_snapshot(values: list[str]) -> dict[str, object]:
    """Explain a capacity decision without confusing it with payload admission.

    Returns:
        The host floor, optional aggregate budget, and reason for refusal.

    """
    available, required, profile, *aggregate = values
    available_bytes = int(available) if available.isdigit() else None
    required_bytes = int(required)
    result: dict[str, object] = {
        "profile": profile,
        "availableBytes": available_bytes,
        "requiredBytes": required_bytes,
        "hostMemoryPressure": host_pressure(),
        "decision": "ready",
    }
    if available_bytes is None:
        result["decision"] = "unreadable-host-memory"
    elif available_bytes < required_bytes:
        result["decision"] = "insufficient-host-memory"
    if aggregate:
        current, budget, ceiling = aggregate
        current_bytes = int(current) if current.isdigit() else None
        result.update(
            aggregateCurrentBytes=current_bytes,
            aggregateRequiredBytes=int(budget),
            aggregateMaxBytes=int(ceiling),
        )
        if result["decision"] == "ready":
            if current_bytes is None:
                result["decision"] = "unreadable-aggregate-memory"
            elif current_bytes + int(budget) > int(ceiling):
                result["decision"] = "insufficient-aggregate-memory"
    return result


def main() -> None:  # ruff: ignore[complex-structure, too-many-branches] - one private lifecycle record
    """Record a lifecycle transition or display unfinished invocations.

    Raises:
        ValueError: The event or scope identity is invalid.

    """
    root = Path(os.environ["XDG_RUNTIME_DIR"]) / "workstation-task-events"
    root.mkdir(mode=0o700, exist_ok=True)
    if sys.argv[1:] == ["status"]:
        for file in sorted(root.glob("workstation-task-*.json")):
            record = json.loads(file.read_text())
            if "completed" not in record:
                sys.stdout.write(json.dumps(record, sort_keys=True) + "\n")
        return
    event, unit, lane, *status = sys.argv[1:]
    if event not in {
        "queued",
        "capacityChecked",
        "admitted",
        "commandFinished",
        "completed",
    }:
        message = "Unknown scheduler event"
        raise ValueError(message)
    if not unit.startswith("workstation-task-") or not unit.endswith(".scope"):
        message = "Invalid scope identity"
        raise ValueError(message)
    if any(
        character not in "abcdefghijklmnopqrstuvwxyz0123456789-." for character in unit
    ):
        message = "Invalid scope characters"
        raise ValueError(message)
    file = root / (unit + ".json")
    record: dict[str, Any] = (
        json.loads(file.read_text()) if file.exists() else {"unit": unit, "lane": lane}
    )
    record[event] = {"unixNs": time.time_ns(), "monotonicNs": time.monotonic_ns()}
    if event == "capacityChecked":
        record["admission"] = capacity_snapshot(status)
    elif status:
        record[event]["exitCode"] = int(status[0])
    if event != "capacityChecked" and len(status) > 1 and status[1]:
        record[event]["scopeResult"] = status[1]
    allocation = (
        Path(os.environ["XDG_RUNTIME_DIR"])
        / "workstation-task-allocations"
        / (unit + ".json")
    )
    if allocation.exists():
        record["memoryAllocation"] = json.loads(allocation.read_text())
    if event == "admitted":
        record["queueWaitMilliseconds"] = (
            record[event]["monotonicNs"] - record["queued"]["monotonicNs"]
        ) / 1_000_000
        if "admission" not in record:
            fields = dict(
                line.split(":", 1)
                for line in Path("/proc/meminfo")
                .read_text(encoding="utf-8")
                .splitlines()
            )
            record["admission"] = {
                "availableBytes": int(fields["MemAvailable"].split()[0]) * 1024,
                "hostMemoryPressure": host_pressure(),
            }
    if event in {"commandFinished", "completed"}:
        observed = scope_resources(unit)
        previous = record.get("nativeResources", {})
        for name in ("MemoryPeak", "MemorySwapPeak", "memoryEvents"):
            if observed.get(name) is None and name in previous:
                observed[name] = previous[name]
        if len(status) > 1 and status[1]:
            observed["scopeResult"] = status[1]
        record["nativeResources"] = observed
    if "admitted" in record and "commandFinished" in record:
        record["executionMilliseconds"] = (
            record["commandFinished"]["monotonicNs"] - record["admitted"]["monotonicNs"]
        ) / 1_000_000
    write_private(file, record)
    identifier = os.environ.get("WORKSTATION_JOB_ID", "")
    directory = Path(os.environ.get("WORKSTATION_JOB_DIRECTORY", "/"))
    if all((
        re.fullmatch(r"[0-9a-f]{32}", identifier),
        directory.name == identifier,
        directory.parent.name == "jobs",
        directory.is_dir(),
    )):
        write_private(directory / "native-resources.json", record)


if __name__ == "__main__":
    main()
