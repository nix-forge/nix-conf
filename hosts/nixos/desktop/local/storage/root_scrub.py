"""Scrub root without active swapfile exclusions, preserving fallback swap state."""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import re
import selectors
import shutil
import signal
import subprocess
import time
from pathlib import Path

GIB = 1024**3


class ScrubError(RuntimeError):
    """A complete scrub cannot proceed safely or its recovery failed."""


def btrfs_executable() -> str:
    """Resolve Btrfs from the packaged service PATH.

    Returns:
        The absolute executable path.

    Raises:
        ScrubError: The required Btrfs utility is unavailable.

    """
    executable = shutil.which("btrfs")
    if executable is None:
        raise ScrubError("Btrfs utility is unavailable")
    return executable


def run(arguments: list[str]) -> None:
    """Run one fixed maintenance command under the owning service deadline."""
    subprocess.run(arguments, check=True)


def swaps(path: Path = Path("/proc/swaps")) -> list[dict]:
    """Read kernel swap state for independent disk capacity accounting.

    Returns:
        Active swap names, sizes, usage and types.

    """
    return [
        {
            "name": parts[0],
            "kind": parts[1],
            "size": int(parts[2]) * 1024,
            "used": int(parts[3]) * 1024,
        }
        for line in path.read_text(encoding="utf-8").splitlines()[1:]
        if (parts := line.split())
    ]


def available(path: Path = Path("/proc/meminfo")) -> int:
    """Read available memory rather than merely unallocated pages.

    Returns:
        The kernel MemAvailable byte count.

    """
    return (
        int(
            next(
                line.split()[1]
                for line in path.read_text(encoding="utf-8").splitlines()
                if line.startswith("MemAvailable:")
            )
        )
        * 1024
    )


def capacity(entries: list[dict], memory: int, swapfile: str) -> None:
    """Require RAM drain margin and eight GiB of other real swap.

    Raises:
        ScrubError: Swap coverage or capacity prevents safe admission.

    """
    files = [item for item in entries if item["kind"] == "file"]
    if any(item["name"] != swapfile for item in files):
        raise ScrubError(
            "Additional active swapfiles prevent proving full root coverage"
        )
    used = sum(item["used"] for item in files)
    disk_free = sum(
        item["size"] - item["used"]
        for item in entries
        if item["name"] != swapfile and not item["name"].startswith("/dev/zram")
    )
    if memory < used + 6 * GIB or disk_free < 8 * GIB:
        raise ScrubError(
            "Root scrub needs six GiB RAM beyond swapfile usage and eight GiB other disk swap free"
        )


def recover(policy: dict) -> None:
    """Restore only the swap state owned by a recorded scrub operation.

    Raises:
        ScrubError: Owned scrub cancellation, guard ownership or swap recovery failed.

    """
    journal = Path(policy["stateDirectory"]) / "root-scrub-operation.json"
    if not journal.exists():
        return
    record = json.loads(journal.read_text(encoding="utf-8"))
    if record.get("started"):
        result = subprocess.run(
            [btrfs_executable(), "scrub", "cancel", "/"],
            capture_output=True,
            check=False,
        )
        if result.returncode not in {0, 2}:
            raise ScrubError("Could not cancel the owned scrub before swap recovery")
    guard = Path(record["guard"])
    if guard.exists() or guard.is_symlink():
        if guard.is_symlink() or guard.read_text(encoding="utf-8") != record["body"]:
            raise ScrubError(
                "Root scrub activation guard changed; inspect before recovery"
            )
        guard.unlink()
    run(["systemctl", "daemon-reload"])
    if record["active"]:
        run(["systemctl", "start", policy["swapUnit"]])
        if not any(item["name"] == policy["swapfile"] for item in swaps()):
            raise ScrubError("Fallback swap did not resume")
    journal.unlink()


def run_scrub(policy: dict, journal: Path) -> float:
    """Observe scrub completion and cancel before headroom becomes unsafe.

    Returns:
        The scrub start timestamp.

    Raises:
        ScrubError: Integrity, execution or coverage checks failed.

    """
    started = time.time()
    record = json.loads(journal.read_text(encoding="utf-8"))
    record["started"] = True
    save_operation(journal, record)
    process = subprocess.Popen([
        btrfs_executable(),
        "scrub",
        "start",
        "-B",
        "--limit",
        "800M",
        "/",
    ])
    descriptor = os.pidfd_open(process.pid)
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(descriptor, selectors.EVENT_READ)
            # MemAvailable has no threshold notification. This bounded
            # 30-second health sample is independent of process exit,
            # which is observed through pidfd, not process polling.
            while not selector.select(30):
                disk_free = sum(
                    item["size"] - item["used"]
                    for item in swaps()
                    if item["name"] != policy["swapfile"]
                    and not item["name"].startswith("/dev/zram")
                )
                if available() < 3 * GIB or disk_free < 2 * GIB:
                    raise ScrubError("Root scrub cancelled to restore memory headroom")
        if process.wait() != 0:
            raise ScrubError("Root scrub reported an integrity or execution failure")
    finally:
        os.close(descriptor)
        if process.poll() is None:
            try:
                run([btrfs_executable(), "scrub", "cancel", "/"])
            finally:
                process.wait()
    if any(item["kind"] == "file" for item in swaps()):
        raise ScrubError(
            "Swapfile activated during scrub; coverage cannot be certified"
        )
    record["started"] = False
    save_operation(journal, record)
    return started


def save_operation(path: Path, record: dict) -> None:
    """Atomically publish complete recovery state without truncating the journal."""
    temporary = path.with_suffix(".tmp")
    with temporary.open("w", encoding="utf-8") as stream:
        json.dump(record, stream)
        stream.flush()
        os.fsync(stream.fileno())
    temporary.chmod(0o600)
    temporary.replace(path)


def scrub(policy: dict) -> None:
    """Reserve maintenance, guard activation and preserve swap state.

    Raises:
        ScrubError: Admission, coverage, integrity or recovery could not be verified.

    """
    state = Path(policy["stateDirectory"])
    state.mkdir(parents=True, exist_ok=True)
    journal = state / "root-scrub-operation.json"
    guard = (
        Path(policy.get("guardDirectory", "/run/systemd/system.control"))
        / (policy["swapUnit"] + ".d")
        / "90-desktop-root-scrub.conf"
    )
    with Path(policy["bulkLock"]).open("a", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if journal.exists() or guard.exists() or guard.is_symlink():
            raise ScrubError(
                "An earlier root scrub needs recovery before another attempt"
            )
        entries = swaps()
        capacity(entries, available(), policy["swapfile"])
        observation = subprocess.run(
            [btrfs_executable(), "scrub", "status", "/"],
            capture_output=True,
            text=True,
            check=False,
        )
        status = observation.stdout
        if (
            observation.returncode
            and "no stats available" not in (status + observation.stderr).lower()
        ):
            raise ScrubError("Existing root scrub state could not be inspected")
        if re.search(r"^Status:\s+running\b", status, re.MULTILINE):
            raise ScrubError("A root scrub is already running outside this operation")
        active = any(item["name"] == policy["swapfile"] for item in entries)
        body = f"[Unit]\nConditionPathExists=!{journal}\n"
        save_operation(journal, {"active": active, "guard": str(guard), "body": body})
        try:
            guard.parent.mkdir(parents=True, exist_ok=True)
            with guard.open("x", encoding="utf-8") as stream:
                stream.write(body)
            run(["systemctl", "daemon-reload"])
            if active:
                run(["systemctl", "stop", policy["swapUnit"]])
            if any(item["kind"] == "file" for item in swaps()):
                raise ScrubError("A swapfile remains active; refusing incomplete scrub")
            started = run_scrub(policy, journal)
        finally:
            recover(policy)
        receipt = state / "checks/root-scrub.json"
        receipt.parent.mkdir(parents=True, exist_ok=True)
        temporary = receipt.with_suffix(".tmp")
        temporary.write_text(
            json.dumps({
                "completed": time.time(),
                "started": started,
                "result": "success",
                "scope": "root-without-active-swapfiles",
            })
            + "\n",
            encoding="utf-8",
        )
        temporary.chmod(0o644)
        temporary.replace(receipt)


def main() -> None:
    """Dispatch the service and its independent failure recovery action."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("policy", type=Path)
    parser.add_argument("action", choices=["run", "recover"])
    args = parser.parse_args()

    def interrupted(_signal: int, _frame: object) -> None:
        """Turn cancellation into normal maintenance failure and cleanup.

        Raises:
            ScrubError: Root scrub cancellation was requested.

        """
        raise ScrubError("Root scrub interrupted")

    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    policy = json.loads(args.policy.read_text(encoding="utf-8"))
    if args.action == "run":
        scrub(policy)
    else:
        recover(policy)


if __name__ == "__main__":
    main()
