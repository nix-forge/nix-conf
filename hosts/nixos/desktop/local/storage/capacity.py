"""Collect dead Nix paths and admit finite work against one capacity policy."""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from typing import Any

BTRFS_SUBVOLUME_INODE = 256
MIB = 1024 * 1024
MAX_REQUEST_DIGITS = 12
MAX_COLLECTION_LOG_BYTES = 64 * 1024
COLLECTION_READ_BYTES = 8192
MAX_COLLECTION_HISTORY_BYTES = 1024 * 1024


def write_json(path: Path, value: object) -> None:
    """Replace a private receipt without exposing an incomplete generation."""
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        with os.fdopen(descriptor, "w") as stream:
            json.dump(value, stream)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        Path(temporary).replace(path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def read_json(path: Path) -> dict[str, Any]:
    """Read optional prior state; missing state has no acknowledgements.

    Returns:
        The previous object, or an empty object when no receipt exists.

    Raises:
        TypeError: The stored JSON is not an object.

    """
    try:
        result = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}
    if not isinstance(result, dict):
        raise TypeError("Capacity state must be an object")
    return result


def probe(path: str) -> dict[str, Any]:
    """Identify the underlying filesystem, including Btrfs subvolume aliases.

    Returns:
        The filesystem identity, mount point and user-available bytes.

    Raises:
        FileNotFoundError: The mount inspection command is unavailable.
        ValueError: Access would trigger an unmounted optional volume.

    """
    target = str(Path(path).absolute())
    findmnt = shutil.which("findmnt")
    if findmnt is None:
        raise FileNotFoundError("findmnt is unavailable")
    result = subprocess.run(
        [
            findmnt,
            "--nocanonicalize",
            "--json",
            "--target",
            target,
            "--output",
            "UUID,TARGET,FSTYPE",
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    mount = json.loads(result.stdout)["filesystems"][0]
    if mount.get("fstype") == "autofs":
        # --target without canonicalization can report the autofs layer even
        # while a real filesystem is stacked above it. Inspect the static
        # mount table before deciding whether path access would wake a disk.
        layers = subprocess.run(
            [
                findmnt,
                "--nocanonicalize",
                "--list",
                "--json",
                "--mountpoint",
                mount["target"],
                "--output",
                "UUID,TARGET,FSTYPE",
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        real = [
            item
            for item in json.loads(layers.stdout)["filesystems"]
            if item.get("target") == mount["target"]
            and item.get("fstype") not in {None, "", "autofs"}
        ]
        if not real:
            raise ValueError("Required storage is an unmounted automount")
        mount = real[-1]
    identity = mount["uuid"] or f"device:{Path(target).stat().st_dev}"
    usage = os.statvfs(target)
    return {
        "identity": identity,
        "mount": mount["target"],
        "available": usage.f_bavail * usage.f_frsize,
    }


def mounted(config: dict[str, Any]) -> dict[str, Any]:
    """Refuse an absent data mount instead of observing its root fallback.

    Returns:
        A verified mounted filesystem sample.

    Raises:
        ValueError: The configured mount is absent.

    """
    sample = probe(config["path"])
    if config.get("requireMount", True) and sample["mount"] != config["path"]:
        message = f"Required storage is not mounted: {config['path']}"
        raise ValueError(message)
    return sample


def cache_guard(policy: dict[str, Any]) -> dict[str, bool]:
    """Refuse cache fallback on root before any manual or scheduled Restic work.

    Returns:
        Readiness only after the real data mount and private cache boundary exist.

    Raises:
        ValueError: The cache is missing, redirected, or outside its subvolume.

    """
    cache = policy["cache"]
    mounted({"path": cache["mount"]})
    root = Path(cache["root"])
    metadata = root.stat()
    if (
        root.resolve(strict=True) != root
        or metadata.st_ino != BTRFS_SUBVOLUME_INODE
        or metadata.st_uid != 0
        or metadata.st_mode & 0o077
    ):
        raise ValueError("The private cache subvolume is not ready")
    for name in ("RESTIC_CACHE_DIR", "TMPDIR"):
        value = Path(os.environ.get(name, ""))
        if (
            not value.is_absolute()
            or value.resolve() != value
            or not value.is_relative_to(root)
        ):
            message = f"{name} is outside the prepared cache subvolume"
            raise ValueError(message)
        if name == "TMPDIR" and not value.is_dir():
            raise ValueError("The prepared cache temporary directory is absent")
    return {"ready": True}


def severity(available: int, limits: dict[str, int], previous: str) -> str:
    """Apply independent warning/critical recovery thresholds.

    Returns:
        The healthy, warning or critical capacity state.

    """
    if available < limits["criticalBytes"] or (
        previous == "critical" and available < limits["criticalRecoveryBytes"]
    ):
        return "critical"
    if available < limits["warningBytes"] or (
        previous in {"warning", "critical"}
        and available < limits["warningRecoveryBytes"]
    ):
        return "warning"
    return "healthy"


def status(policy: dict[str, Any]) -> dict[str, Any]:
    """Publish capacity transitions and collector failure/freshness evidence.

    Returns:
        The sample and actionable capacity warnings.

    """
    state_path = Path(policy["stateDirectory"]) / "capacity.json"
    previous = read_json(state_path)
    samples: dict[str, Any] = {}
    messages = []
    for limits in policy["filesystems"]:
        path = limits["path"]
        try:
            sample = mounted(limits)
            level = severity(
                sample["available"],
                limits,
                previous
                .get("filesystems", {})
                .get(path, {})
                .get("severity", "healthy"),
            )
            samples[path] = {"availableBytes": sample["available"], "severity": level}
            if level != "healthy":
                messages.append(
                    f"{level.capitalize()} storage capacity on {path}: {sample['available'] // MIB} MiB available"
                )
        except OSError, ValueError, KeyError, subprocess.SubprocessError:
            samples[path] = {"severity": "unknown"}
            messages.append(f"Storage capacity inspection failed: {path}")
    for cache in policy.get("cacheBudgets", []):
        try:
            messages.extend(cache_messages(cache))
        except OSError, ValueError, subprocess.SubprocessError:
            messages.append("Regenerable cache size could not be inspected")
    receipt = read_json(Path(policy["stateDirectory"]) / "collection.json")
    age = time.time() - receipt.get("completed", 0)
    if not 0 <= age <= policy["collectorStaleSeconds"]:
        messages.append("Storage collection results are missing or stale")
    if receipt.get("status") in {"failed", "unreclaimable"} or receipt.get(
        "previousFailure"
    ):
        messages.append(
            "Nix collection could not restore its capacity target; inspect rooted outputs and other writers"
        )
    output = {"checked": time.time(), "filesystems": samples, "messages": messages}
    write_json(state_path, output)
    return output


def cache_messages(cache: dict[str, Any]) -> list[str]:
    """Measure only the bounded-scope regenerable cache, never the whole home.

    Returns:
        A warning when the active cache exceeds its soft budget.

    Raises:
        FileNotFoundError: The size inspection command is unavailable.

    """
    du = shutil.which("du")
    if du is None:
        raise FileNotFoundError("Cache inspection is unavailable")
    result = subprocess.run(
        [du, "--summarize", "--one-file-system", "--block-size=1", cache["path"]],
        capture_output=True,
        text=True,
        check=True,
    )
    allocated = int(result.stdout.split()[0])
    if allocated > cache["warningBytes"]:
        return [
            "Active Restic cache exceeds its storage budget; review cache placement and repository growth"
        ]
    return []


def admission(
    policy: dict[str, Any],
    requests: list[tuple[str, int]],
    *,
    recovery: bool = False,
    snapshot: bool = False,
) -> dict[str, Any]:
    """Combine requests by filesystem UUID and reject insufficient projected space.

    Returns:
        The decision and per-filesystem projected-space evidence.

    Raises:
        ValueError: A request is invalid or its filesystem is unavailable.

    """
    known = {}
    absent = []
    for limits in policy["filesystems"]:
        try:
            sample = mounted(limits)
            known[sample["identity"]] = (limits, sample)
        except OSError, ValueError, KeyError, subprocess.SubprocessError:
            absent.extend([limits["path"], *limits.get("aliases", [])])
    required: dict[str, int] = {}
    for path, amount in requests:
        if amount < 0 or not Path(path).is_absolute():
            raise ValueError(
                "Disk requests require an absolute path and nonnegative bytes"
            )
        declared = str(Path(path).absolute())
        if any(declared == base or declared.startswith(f"{base}/") for base in absent):
            raise ValueError("Requested storage mount is unavailable")
        resolved = str(Path(path).resolve(strict=True))
        if any(resolved == base or resolved.startswith(f"{base}/") for base in absent):
            raise ValueError("Requested storage mount is unavailable")
        sample = probe(resolved)
        identity = sample["identity"]
        if identity not in known:
            raise ValueError("Requested filesystem has no capacity policy")
        required[identity] = required.get(identity, 0) + amount
    results = []
    for identity, amount in required.items():
        limits, sample = known[identity]
        floor = (
            limits["criticalBytes"]
            if snapshot
            else 0
            if recovery
            else limits["admissionBytes"]
        )
        results.append({
            "path": limits["path"],
            "availableBytes": sample["available"],
            "additionalBytes": amount,
            "minimumRemainingBytes": floor,
            "admitted": sample["available"] - amount >= floor,
        })
    return {
        "checked": time.time(),
        "admitted": all(item["admitted"] for item in results),
        "recovery": recovery,
        "filesystems": results,
    }


def collect(policy: dict[str, Any], *, force: bool = False) -> dict[str, Any]:
    """Take the shared workload lock, recheck pressure, then collect once.

    Returns:
        The durable collection or skip receipt.

    """
    receipt_path = Path(policy["stateDirectory"]) / "collection.json"
    limits = next(item for item in policy["filesystems"] if item["path"] == "/")
    started = time.time()
    before = mounted(limits)["available"]
    result: dict[str, Any] = {
        "started": started,
        "beforeBytes": before,
        "status": "skipped",
    }
    old = read_json(receipt_path)
    failure = (
        {key: old[key] for key in ("status", "completed", "afterBytes")}
        if old.get("status") in {"failed", "unreclaimable"}
        else old.get("previousFailure", {})
    )
    cooldown = (
        bool(failure)
        and started - failure.get("completed", 0) < policy["retrySeconds"]
        and before >= failure.get("afterBytes", 0) - policy["retryDropBytes"]
    )
    if before < policy["collectBelowBytes"] and failure:
        result["previousFailure"] = failure
    if before < policy["collectBelowBytes"] and cooldown and not force:
        return old
    if before < policy["collectBelowBytes"]:
        # The native service owns the finite deadline and all child lifetimes.
        # Lock admission and blocking waitpid avoid status-probe loops.
        with Path(policy["bulkLock"]).open("r+", encoding="utf-8") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                result.update({
                    "status": "deferred",
                    "afterBytes": before,
                    "completed": time.time(),
                })
                save_collection(policy, result)
                return result
            minimum_memory = policy.get("minimumMemoryAvailableBytes", 0)
            if not memory_admissible(minimum_memory):
                result.update({
                    "status": "deferred-memory",
                    "afterBytes": before,
                    "completed": time.time(),
                })
                save_collection(policy, result)
                return result
            before = mounted(limits)["available"]
            result["beforeBytes"] = before
            if before < policy["collectBelowBytes"]:
                log = Path(policy["stateDirectory"]) / "collection.log"
                exit_code = run_collection(
                    [
                        policy["nixStore"],
                        "--store",
                        "daemon",
                        "--gc",
                        "--max-freed",
                        str(policy["collectTargetBytes"] - before),
                    ],
                    log,
                )
                after = mounted(limits)["available"]
                result.update({
                    "exitCode": exit_code,
                    "afterBytes": after,
                    "targetReached": after >= policy["collectTargetBytes"],
                })
                result["status"] = (
                    "failed"
                    if exit_code
                    else "collected"
                    if after >= policy["collectBelowBytes"]
                    else "unreclaimable"
                )
    if result["status"] in {"collected", "skipped"}:
        result.pop("previousFailure", None)
    result.setdefault("afterBytes", mounted(limits)["available"])
    result["completed"] = time.time()
    save_collection(policy, result)
    return result


def memory_admissible(minimum: int) -> bool:
    """Use the configured daemon headroom without a second memory scheduler.

    Returns:
        Whether the current sample can support collection; unknown fails closed.

    """
    if minimum == 0:
        return True
    try:
        text = Path("/proc/meminfo").read_text(encoding="utf-8")
    except OSError:
        return False
    available = re.search(r"^MemAvailable:\s+(\d+) kB$", text, re.MULTILINE)
    return available is not None and int(available[1]) * 1024 >= minimum


def save_collection(policy: dict[str, Any], result: dict[str, Any]) -> None:
    """Preserve finite outcomes in bounded history as well as the latest receipt."""
    directory = Path(policy["stateDirectory"])
    write_json(directory / "collection.json", result)
    history = directory / "collection-history.jsonl"
    if history.exists() and history.stat().st_size > MAX_COLLECTION_HISTORY_BYTES:
        history.replace(history.with_suffix(".jsonl.1"))
    descriptor = os.open(history, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
        stream.write(json.dumps(result) + "\n")


def run_collection(command: list[str], log: Path) -> int:
    """Drain command output continuously while retaining only a small error tail.

    Returns:
        The actual native client's exit status.

    Raises:
        RuntimeError: The child output descriptor was not created.

    """
    process = subprocess.Popen(
        command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
    )
    tail = b""
    try:
        if process.stdout is None:
            raise RuntimeError("Collection output descriptor is unavailable")
        while block := process.stdout.read(COLLECTION_READ_BYTES):
            tail = (tail + block)[-MAX_COLLECTION_LOG_BYTES:]
        status_code = process.wait()
    finally:
        if process.stdout is not None:
            process.stdout.close()
        if process.returncode is None:
            process.terminate()
            process.wait()
    descriptor = os.open(log, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(tail)
    return status_code


def parse_request(value: str) -> tuple[str, int]:
    """Parse an explicit additional peak allocation in MiB.

    Returns:
        The absolute-path declaration and requested byte count.

    Raises:
        ValueError: The request is malformed.

    """
    path, amount = value.rsplit("=", 1)
    if not amount.isdecimal() or len(amount) > MAX_REQUEST_DIGITS:
        raise ValueError("Disk request must be PATH=nonnegative_MiB")
    return path, int(amount) * MIB


def main() -> int:
    """Run a finite collection, admission check, or health sample.

    Returns:
        Zero on success or a capacity/preflight failure code.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--policy", type=Path, required=True)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("status")
    subparsers.add_parser("cache")
    snapshot = subparsers.add_parser("snapshot")
    snapshot.add_argument("path")
    collector = subparsers.add_parser("collect")
    collector.add_argument("--force", action="store_true")
    admit = subparsers.add_parser("admit")
    admit.add_argument("--disk-mib", action="append", default=[])
    admit.add_argument(
        "--recovery",
        action="store_true",
        help="Allow explicit recovery work without ordinary free-space floors",
    )
    admit.add_argument("--receipt", type=Path)
    args = parser.parse_args()
    try:
        policy = json.loads(args.policy.read_text(encoding="utf-8"))
        return execute(policy, args)
    except (
        OSError,
        ValueError,
        TypeError,
        KeyError,
        StopIteration,
        subprocess.SubprocessError,
    ) as error:
        print(f"Storage capacity check failed: {error}", file=sys.stderr)
        return 75


def execute(policy: dict[str, Any], args: argparse.Namespace) -> int:
    """Dispatch one requested capacity operation.

    Returns:
        Zero on success or 75 when projected capacity is insufficient.

    Raises:
        ValueError: Disk declarations have an invalid shape.

    """
    if args.command in {"status", "cache"}:
        result = {"status": status, "cache": cache_guard}[args.command](policy)
    elif args.command == "collect":
        result = collect(policy, force=args.force)
    elif args.command == "snapshot":
        result = admission(policy, [("/", 0), (args.path, 0)], snapshot=True)
        if not result["admitted"]:
            print(json.dumps(result), file=sys.stderr)
            return 75
    else:
        declarations = args.disk_mib or json.loads(
            os.environ.get("WORKSTATION_DISK_REQUESTS", "[]")
        )
        if not isinstance(declarations, list) or not all(
            isinstance(value, str) for value in declarations
        ):
            raise ValueError(
                "Disk declarations must be a JSON list of PATH=MiB strings"
            )
        requests = (
            [parse_request(value) for value in declarations]
            if declarations
            else [
                ("/", 0 if args.recovery else policy["defaultAdditionalBytes"]),
                (str(Path.cwd()), 0),
            ]
        )
        if declarations:
            requests.extend([("/", 0), (str(Path.cwd()), 0)])
        result = admission(policy, requests, recovery=args.recovery)
        if args.receipt:
            write_json(args.receipt, result)
        if not result["admitted"]:
            print(json.dumps(result), file=sys.stderr)
            return 75
    print(json.dumps(result))
    if args.command == "collect" and result["status"] in {"failed", "unreclaimable"}:
        return 75
    return 0


if __name__ == "__main__":
    sys.exit(main())
