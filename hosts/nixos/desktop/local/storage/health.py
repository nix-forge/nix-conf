"""Report storage failures without exposing device identifiers or credentials."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import time
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from typing import Any

MAX_REPORT_AGE = 7200


def run(arguments: list[str]) -> subprocess.CompletedProcess[str]:
    """Run a fixed installed utility, preserving failure status.

    Returns:
        The completed process and its exit status.

    """
    return subprocess.run(
        arguments, check=False, capture_output=True, text=True, shell=False
    )


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
        result = run(["systemctl", "show", unit, "--property=ActiveState", "--value"])
        if result.returncode or result.stdout.strip() == "failed":
            messages.append(f"Service needs attention: {unit}")
    # Keep the report independent of private repository file contents.
    backup = run(["desktop-backup-check", "status"])
    if backup.returncode:
        messages.extend(
            line[2:] for line in backup.stdout.splitlines() if line.startswith("- ")
        )
        if not backup.stdout:
            messages.append("Backup status could not be checked")
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
        if time.time() - report["checked"] > MAX_REPORT_AGE:
            return [
                "Storage health results are stale; inspect desktop-storage-health.service"
            ]
        return report["messages"]
    except (OSError, ValueError, TypeError, KeyError):
        return ["Storage health has not been checked yet"]


def main() -> int:
    """Run monitoring, status display or deduplicated desktop notifications.

    Returns:
        The command exit status.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("policy", type=Path)
    parser.add_argument(
        "action", choices=["status", "refresh", "notify"], default="status", nargs="?"
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
    if args.action == "notify":
        directory = (
            Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache")))
            / "desktop-storage"
        )
        directory.mkdir(parents=True, exist_ok=True)
        digest = hashlib.sha256(json.dumps(messages).encode()).hexdigest()
        receipt = directory / "notification"
        if receipt.exists() and receipt.read_text() == digest:
            return 0
        if messages:
            result = run([
                "notify-send",
                "--urgency=critical",
                "--expire-time=0",
                "Storage needs attention",
                "\n".join(messages) + "\nRun desktop-storage-status for details.",
            ])
            if result.returncode:
                return 1
        receipt.write_text(digest)
        return 0
    print(
        "\n".join(f"- {message}" for message in messages)
        if messages
        else "Storage checks passed"
    )
    return 1 if messages else 0


if __name__ == "__main__":
    raise SystemExit(main())
