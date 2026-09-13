"""Report storage failures without exposing device identifiers or credentials."""

from __future__ import annotations

import argparse
import contextlib
import fcntl
import hashlib
import json
import math
import os
import shutil
import signal
import subprocess
import time
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from typing import Any

MAX_REPORT_AGE = 7200
MAX_CLOCK_SKEW = 60


def run(
    arguments: list[str], timeout: int = 30, payload: str | None = None
) -> subprocess.CompletedProcess[str]:
    """Run a fixed installed utility, preserving failure status.

    Returns:
        The completed process and its exit status.

    Raises:
        subprocess.SubprocessError: The command left unfinished child processes.

    """
    process = subprocess.Popen(
        arguments,
        stdin=subprocess.PIPE if payload is not None else subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        stdout, stderr = process.communicate(input=payload, timeout=timeout)
        try:
            os.killpg(process.pid, 0)
        except ProcessLookupError:
            return subprocess.CompletedProcess(
                arguments, process.returncode, stdout, stderr
            )
        raise subprocess.SubprocessError(
            "Health command left unfinished child processes"
        )
    finally:
        # Do not call communicate() again after timeout: an escaped child may
        # retain its pipes. Kill the owned group, reap the leader, close pipes.
        with contextlib.suppress(ProcessLookupError):
            os.killpg(process.pid, signal.SIGKILL)
        try:
            process.wait(timeout=5)
        finally:
            for stream in (process.stdin, process.stdout, process.stderr):
                if stream is not None:
                    stream.close()


def collect(policy: dict[str, Any]) -> list[str]:
    """Collect actionable failures without putting raw device logs in notifications.

    Returns:
        The actionable warnings.

    """
    messages = []
    if not policy["encrypted"]:
        messages.append("Disk encryption migration is not enabled")
    for path in policy["mounts"]:
        if run(["mountpoint", "-q", path]).returncode:
            messages.append(f"Storage is not mounted: {path}")
            continue
        usage = shutil.disk_usage(path)
        used_percent = 100 * (usage.total - usage.free) / usage.total
        if used_percent >= policy["warningPercent"]:
            messages.append(f"Low free space on {path}: {used_percent:.0f}% used")
        if run(["btrfs", "device", "stats", "--check", path]).returncode:
            messages.append(f"Btrfs reports device errors or cannot inspect {path}")
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
        except (OSError, ValueError, TypeError, KeyError, subprocess.SubprocessError):  # ruff: ignore[try-except-in-loop] - continue checking independent services
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
    except (OSError, ValueError, TypeError, KeyError):
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
        One if delivery is unavailable or failed; zero after delivery or deduplication.

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
        except (OSError, ValueError):
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
            return 1
        try:
            result = run(arguments, payload=json.dumps(event) + "\n")
        except (OSError, subprocess.SubprocessError):
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
