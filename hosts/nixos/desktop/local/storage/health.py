"""Report storage failures without exposing device identifiers or credentials."""

from __future__ import annotations

import argparse
import contextlib
import fcntl
import hashlib
import json
import math
import os
import re
import selectors
import shutil
import signal
import subprocess
import time
from pathlib import Path
from typing import TYPE_CHECKING

from notification_process import communicate, defer_cancellation

if TYPE_CHECKING:
    from typing import Any

MAX_REPORT_AGE = 7200
MAX_CLOCK_SKEW = 60


def _reap(process: subprocess.Popen[str]) -> None:
    """Bound exit observation after communication using a Linux pidfd.

    Communication owns its observer until exit. A kernel-uninterruptible child
    can delay that preceding cleanup; the service manager is the outer owner.

    Raises:
        subprocess.TimeoutExpired: The killed child has not exited within five seconds.

    """
    if process.returncode is not None:
        return
    descriptor = os.pidfd_open(process.pid)
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(descriptor, selectors.EVENT_READ)
            if not selector.select(5):
                raise subprocess.TimeoutExpired(process.args, 5)
        _, status = os.waitpid(process.pid, 0)
        process.returncode = os.waitstatus_to_exitcode(status)
    finally:
        os.close(descriptor)


def run(
    arguments: list[str], timeout: int = 30, payload: str | None = None
) -> subprocess.CompletedProcess[str]:
    """Run a fixed installed utility, preserving failure status.

    Returns:
        The completed process and its exit status.

    Raises:
        subprocess.SubprocessError: The command left unfinished child processes.
        ChildProcessError: Another waiter violated exclusive child ownership.

    """
    process = subprocess.Popen(
        arguments,
        stdin=subprocess.PIPE if payload is not None else subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    owns_child = True
    try:
        stdout, stderr = communicate(process, input=payload, timeout=timeout)
        if _unfinished_group(process.pid):
            raise subprocess.SubprocessError(
                "Health command left unfinished child processes"
            )
    except ChildProcessError:
        owns_child = False
        raise
    finally:
        with defer_cancellation():
            # Do not call communicate() again after timeout: an escaped child may
            # retain its pipes. Kill the owned group, reap the leader, close pipes.
            if owns_child:
                with contextlib.suppress(ProcessLookupError):
                    os.killpg(process.pid, signal.SIGKILL)
            try:
                if owns_child:
                    _reap(process)
            finally:
                for stream in (process.stdin, process.stdout, process.stderr):
                    if stream is not None:
                        stream.close()
    return subprocess.CompletedProcess(arguments, process.returncode, stdout, stderr)


def _unfinished_group(leader: int) -> bool:
    """Inspect one finite group snapshot while the retained leader owns its PID.

    A snapshot is diagnostic evidence. Cleanup kills the owned group before
    reaping even when racing descendants were absent from this snapshot.

    Returns:
        Whether another process was observed in the command's process group.

    """
    for entry in Path("/proc").iterdir():
        if not entry.name.isdecimal() or int(entry.name) == leader:
            continue
        try:
            fields = (entry / "stat").read_bytes().rsplit(b")", 1)[1].split()
        except FileNotFoundError, ProcessLookupError:  # ruff: ignore[try-except-continue] - A process may exit during this finite snapshot.
            continue
        if int(fields[2]) == leader:
            return True
    return False


def mount_messages(policy: dict[str, Any], path: str) -> list[str]:
    """Inspect a real mount without traversing an inactive automount.

    Returns:
        Independent capacity and filesystem warnings for this volume.

    """
    result = run([
        "findmnt",
        "--nocanonicalize",
        "--list",
        "--json",
        "--mountpoint",
        path,
        "--output",
        "TARGET,FSTYPE",
    ])
    if result.returncode:
        return [f"Storage is not mounted: {path}"]
    layers = json.loads(result.stdout)["filesystems"]
    real = [
        item
        for item in layers
        if item.get("target") == path and item.get("fstype") not in {None, "", "autofs"}
    ]
    if not real:
        return [f"Storage is not mounted: {path}"]
    messages = []
    usage = shutil.disk_usage(path)
    used_percent = 100 * (usage.total - usage.free) / usage.total
    if not policy.get("capacityCommand") and used_percent >= policy["warningPercent"]:
        messages.append(f"Low free space on {path}: {used_percent:.0f}% used")
    messages.extend(btrfs_messages(policy, path))
    messages.extend(allocation_messages(policy, path))
    return messages


def collect(policy: dict[str, Any]) -> list[str]:
    """Collect actionable failures without putting raw device logs in notifications.

    Returns:
        The actionable warnings.

    """
    messages = []
    if not policy["encrypted"]:
        messages.append("Disk encryption migration is not enabled")
    capacity_command = policy.get("capacityCommand", [])
    messages.extend(capacity_messages(capacity_command))
    for path in policy["mounts"]:
        try:
            messages.extend(mount_messages(policy, path))
        except (
            OSError,
            ValueError,
            KeyError,
            IndexError,
            TypeError,
            subprocess.SubprocessError,
        ):
            messages.append(f"Storage inspection failed: {path}")
    for unit in policy["units"]:
        result = run(["systemctl", "show", unit, "--property=LoadState,ActiveState"])
        state = dict(
            line.split("=", 1) for line in result.stdout.splitlines() if "=" in line
        )
        if (
            result.returncode
            or state.get("LoadState") != "loaded"
            or state.get("ActiveState") == "failed"
        ):
            messages.append(f"Service needs attention: {unit}")
    # Keep the report independent of private repository file contents.
    backup = run(["desktop-backup-check", "status"])
    if backup.returncode:
        messages.extend(
            line[2:] for line in backup.stdout.splitlines() if line.startswith("- ")
        )
        if not backup.stdout:
            messages.append("Backup status could not be checked")
    messages.extend(probe_messages(policy))
    return messages


def capacity_payload(result: subprocess.CompletedProcess[str]) -> list[str]:
    """Validate the capacity helper's public result.

    Returns:
        The actionable capacity messages.

    Raises:
        ValueError: The helper failed or its result is malformed.

    """
    if result.returncode:
        raise ValueError("Capacity collector failed")
    capacity = json.loads(result.stdout)
    if not isinstance(capacity["messages"], list) or not all(
        isinstance(message, str) for message in capacity["messages"]
    ):
        raise ValueError("Capacity result is malformed")
    return capacity["messages"]


def capacity_messages(command: list[str]) -> list[str]:
    """Keep failed capacity inspection distinct from healthy storage.

    Returns:
        Capacity warnings, or one inspection-failure warning.

    """
    if not command:
        return []
    try:
        return capacity_payload(run(command))
    except OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError:
        return ["Storage capacity policy could not be checked"]


def device_counters(text: str) -> dict[str, int]:
    """Parse every device counter without exposing device identifiers in alerts.

    Returns:
        Counters keyed by the complete private device/counter name.

    Raises:
        ValueError: Output does not contain valid nonnegative device counters.

    """
    values = {}
    for line in text.splitlines():
        key, value = line.rsplit(None, 1)
        if not key.startswith("[") or "]." not in key or not value.isdecimal():
            raise ValueError("Malformed Btrfs device statistics")
        values[key] = int(value)
    if not values:
        raise ValueError("Missing Btrfs device statistics")
    return values


def counter_messages(
    path: str, current: dict[str, int], previous: dict[str, int]
) -> list[str]:
    """Differentiate increasing errors, historical totals and counter resets.

    Returns:
        Device-free alert labels; no counters are reset or acknowledged.

    """
    if any(value > previous.get(key, value) for key, value in current.items()):
        return [f"New Btrfs device errors on {path}; investigate integrity"]
    if any(value < previous.get(key, value) for key, value in current.items()):
        return [
            f"Btrfs device counters decreased or were reset on {path}; review preserved evidence"
        ]
    if any(current.values()):
        return [
            f"Historical Btrfs device errors remain on {path}; latest scrub and counter deltas need review"
        ]
    return []


def btrfs_messages(policy: dict[str, Any], path: str) -> list[str]:
    """Preserve the last per-device observation under root-only permissions.

    Returns:
        Integrity warnings, or an explicit statistics inspection failure.

    """
    report = Path(policy["stateDirectory"]) / (
        "btrfs-" + hashlib.sha256(path.encode()).hexdigest() + ".json"
    )
    try:
        return sample_btrfs(report, path)
    except OSError, ValueError, TypeError, KeyError, subprocess.SubprocessError:
        return [f"Btrfs device statistics could not be inspected: {path}"]


def sample_btrfs(report: Path, path: str) -> list[str]:
    """Sample and persist per-device evidence under a root-owned report path.

    Returns:
        Integrity warning labels.

    Raises:
        TypeError: A persisted sample is malformed.

    """
    previous = json.loads(report.read_text(encoding="utf-8")) if report.exists() else {}
    if not isinstance(previous, dict):
        raise TypeError("Malformed Btrfs sample")
    result = run(["btrfs", "device", "stats", path])
    if result.returncode:
        return [f"Btrfs device statistics could not be inspected: {path}"]
    current = device_counters(result.stdout)
    messages = counter_messages(path, current, previous.get("counters", {}))
    # Keep one previous sample as evidence when a deliberate reset occurs.
    value = {
        "checked": time.time(),
        "counters": current,
        "previous": previous.get("counters", {}),
    }
    descriptor = os.open(
        str(report) + ".tmp", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600
    )
    with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
        json.dump(value, stream)
    Path(str(report) + ".tmp").replace(report)
    return messages


def allocation_values(text: str) -> dict[str, int]:
    """Separate allocator headroom from logical files and allocated-group fullness.

    Returns:
        Explicitly labeled Btrfs metadata and reserve byte counters.

    Raises:
        ValueError: Required installed-version usage fields are missing.

    """
    metadata = re.findall(
        r"^Metadata,[^:]+: Size:(\d+), Used:(\d+)", text, re.MULTILINE
    )
    reserve = re.search(r"Global reserve:\s*(\d+)\s+\(used:\s*(\d+)\)", text)
    unallocated = re.search(r"Device unallocated:\s*(\d+)", text)
    if not metadata or reserve is None or unallocated is None:
        raise ValueError("Btrfs allocation fields are unavailable")
    return {
        "metadataAllocatedLogicalBytes": sum(int(size) for size, _ in metadata),
        "metadataUsedLogicalBytes": sum(int(used) for _, used in metadata),
        "globalReserveBytes": int(reserve[1]),
        "globalReserveUsedBytes": int(reserve[2]),
        "unallocatedDeviceBytes": int(unallocated[1]),
    }


def allocation_messages(policy: dict[str, Any], path: str) -> list[str]:
    """Warn on allocator pressure without treating a full data group as a full disk.

    Returns:
        Allocator warnings or an explicit inspection failure.

    """
    try:
        result = run(["btrfs", "filesystem", "usage", "--raw", path])
        values = allocation_values(result.stdout) if result.returncode == 0 else {}
        return save_allocation(policy, path, values)
    except OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError:
        return [f"Btrfs allocation could not be inspected: {path}"]


def save_allocation(
    policy: dict[str, Any], path: str, values: dict[str, int]
) -> list[str]:
    """Keep a private allocator sample and classify simultaneous space pressure.

    Returns:
        Warnings for emergency reserve use or low metadata allocation headroom.

    Raises:
        ValueError: The sample is unavailable.

    """
    if not values:
        raise ValueError("Btrfs allocation sample is unavailable")
    report = Path(policy["stateDirectory"]) / (
        "allocation-" + hashlib.sha256(path.encode()).hexdigest() + ".json"
    )
    descriptor = os.open(
        str(report) + ".tmp", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600
    )
    with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
        json.dump({"checked": time.time(), **values}, stream)
    Path(str(report) + ".tmp").replace(report)
    metadata_free = (
        values["metadataAllocatedLogicalBytes"] - values["metadataUsedLogicalBytes"]
    )
    if values["globalReserveUsedBytes"]:
        return [f"Btrfs emergency metadata reserve is in use: {path}"]
    if metadata_free < 256 * 1024 * 1024 and values["unallocatedDeviceBytes"] < 1024**3:
        return [f"Btrfs metadata allocation headroom is low: {path}"]
    return []


def probe_messages(policy: dict[str, Any]) -> list[str]:
    """Check bounded service commands and successful-work receipts.

    Returns:
        Redacted failure labels, without command output or private paths.

    """
    messages = []
    for name, probe in policy.get("probes", {}).items():
        try:  # ruff: ignore[too-many-statements-in-try-clause] - report independent probe failures
            if (
                probe["command"]
                and run(probe["command"], probe["timeoutSeconds"]).returncode
            ):
                messages.append(f"Service probe failed: {name}")
            if probe["receipt"]:
                record = json.loads(Path(probe["receipt"]).read_text(encoding="utf-8"))
                completed = record["completed"]
                age = time.time() - completed
                if (
                    not math.isfinite(age)
                    or age < -MAX_CLOCK_SKEW
                    or age > probe["maxAgeSeconds"]
                    or record.get("result", "success") != "success"
                ):
                    messages.append(f"Successful work is missing or overdue: {name}")
        except OSError, ValueError, TypeError, KeyError, subprocess.SubprocessError:
            messages.append(f"Service probe unavailable: {name}")
    return messages


def save(policy: dict[str, Any], messages: list[str]) -> None:
    """Atomically publish a redacted status report."""
    directory = Path(policy["stateDirectory"])
    directory.mkdir(mode=0o755, parents=True, exist_ok=True)
    temporary = directory / "health.tmp"
    temporary.write_text(
        json.dumps({"checked": time.time(), "messages": messages}) + "\n"
    )
    temporary.chmod(0o644)
    temporary.replace(directory / "health.json")


def read(policy: dict[str, Any]) -> list[str]:
    """Read the status report, rejecting absent or stale monitoring results.

    Returns:
        The actionable warnings.

    """
    try:
        report = json.loads(
            (Path(policy["stateDirectory"]) / "health.json").read_text()
        )
        age = time.time() - report["checked"]
        if not math.isfinite(age) or age < -MAX_CLOCK_SKEW or age > MAX_REPORT_AGE:
            return [
                "Storage health results are stale; inspect desktop-storage-health.service"
            ]
        if not isinstance(report["messages"], list) or not all(
            isinstance(item, str) for item in report["messages"]
        ):
            return ["Storage health report is malformed"]
        return report["messages"]
    except OSError, ValueError, TypeError, KeyError:
        return ["Storage health has not been checked yet"]


def deliver(
    policy: dict[str, Any],
    messages: list[str],
    *,
    desktop: bool = False,
    test: bool = False,
) -> int:
    """Acknowledge changed warning/recovery state only after successful delivery.

    Returns:
        One if test delivery is unavailable or a configured command failed;
        zero otherwise.

    """
    directory = (
        Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache")))
        / "desktop-storage"
        if desktop
        else Path(policy["stateDirectory"]) / "delivery"
    )
    directory.mkdir(parents=True, mode=0o700, exist_ok=True)
    digest = hashlib.sha256(
        json.dumps(
            {
                "messages": sorted(set(messages)),
                "channel": "desktop" if desktop else policy.get("notificationCommand"),
            },
            sort_keys=True,
        ).encode()
    ).hexdigest()
    event = {
        "event": "test" if test else "warning" if messages else "recovery",
        "messages": messages,
    }
    with (directory / "lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        receipt = directory / "delivered.json"
        try:
            previous = json.loads(receipt.read_text())
        except OSError, ValueError:
            previous = {}
        if not isinstance(previous, dict):
            previous = {}
        pending = directory / ("test-pending.json" if test else "pending.json")
        if not test and previous.get("digest") == digest:
            pending.unlink(missing_ok=True)
            return 0
        # A healthy first sample is a baseline, not a recovery event.
        if not test and not messages and not previous:
            pending.unlink(missing_ok=True)
            return 0
        pending.write_text(json.dumps(event) + "\n")
        pending.chmod(0o600)
        if desktop:
            arguments = [
                "notify-send",
                "--urgency=critical" if messages else "--urgency=normal",
                "--expire-time=0",
                "Workstation needs attention"
                if messages
                else "Workstation checks recovered",
                "\n".join(messages)
                if messages
                else "Previously reported checks now pass.",
            ]
        else:
            arguments = policy.get("notificationCommand") or []
        if not arguments:
            return 1 if test else 0
        try:
            result = run(arguments, payload=json.dumps(event) + "\n")
        except OSError, subprocess.SubprocessError:
            return 1
        if result.returncode:
            return 1
        if not test:
            temporary = receipt.with_suffix(".tmp")
            temporary.write_text(
                json.dumps({
                    "digest": digest,
                    "event": event["event"],
                    "completed": time.time(),
                })
                + "\n"
            )
            temporary.chmod(0o600)
            temporary.replace(receipt)
        pending.unlink(missing_ok=True)
        return 0


def main() -> int:
    """Run monitoring, status display or deduplicated desktop notifications.

    Returns:
        The command exit status.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("policy", type=Path)
    parser.add_argument(
        "action",
        choices=["status", "refresh", "notify", "deliver", "test-delivery"],
        default="status",
        nargs="?",
    )
    args = parser.parse_args()
    policy = json.loads(args.policy.read_text())
    if args.action == "refresh":
        if os.geteuid() != 0:
            parser.error("Refresh requires root")
        messages = collect(policy)
        save(policy, messages)
        print("\n".join(messages) if messages else "Storage checks passed")
        # Warnings live in the report. A failed monitoring process remains a
        # distinct service failure and causes the report to go stale.
        return 0
    messages = read(policy)
    if args.action in {"notify", "deliver", "test-delivery"}:
        return deliver(
            policy,
            messages,
            desktop=args.action == "notify",
            test=args.action == "test-delivery",
        )
    print(
        "\n".join(f"- {message}" for message in messages)
        if messages
        else "Storage checks passed"
    )
    return 1 if messages else 0


if __name__ == "__main__":
    raise SystemExit(main())
