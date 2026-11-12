"""Backup preflight, restore probes and honest 3-2-1-1-0 status.

Repository credentials never appear in reports. Topology fields are operator
claims; successful sample restores do not certify application recovery.
"""

from __future__ import annotations

import argparse
import contextlib
import fcntl
import hashlib
import json
import os
import re
import secrets
import signal
import stat
import subprocess
import tempfile
import time
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Generator
    from typing import Any

MINIMUM_BACKUP_COPIES = 2
PHASES = [
    "backup",
    "integrity",
    "restore",
    "cold-backup",
    "cold-restore",
    "database-backup",
]


class BackupError(ValueError):
    """A preflight or restore condition prevents trusting this backup."""


def run(arguments: list[str]) -> str:
    """Run a fixed utility without a shell and capture private diagnostic output.

    Returns:
        The captured command output.

    """
    return subprocess.run(
        arguments, check=True, capture_output=True, text=True, shell=False
    ).stdout


def private_file(path: str) -> Path:
    """Reject publicly readable or store-backed credentials.

    Returns:
        The validated or prepared file path.

    Raises:
        BackupError: A required security or recovery condition failed.

    """
    candidate = Path(path)
    resolved = candidate.resolve(strict=True)
    info = resolved.stat()
    if (
        not stat.S_ISREG(info.st_mode)
        or info.st_uid != 0
        or stat.S_IMODE(info.st_mode) & 0o077
        or resolved.is_relative_to("/nix/store")
    ):
        raise BackupError(
            "Credential files must be root-owned, private regular files outside the Nix store"
        )
    return candidate


def guard(destination: dict[str, Any]) -> None:
    """Reject unavailable media and backup repositories on a source filesystem.

    Raises:
        BackupError: A required security or recovery condition failed.

    """
    for field in ("repositoryFile", "passwordFile", "environmentFile"):
        if destination.get(field):
            private_file(destination[field])
    for mount in destination["requiredMounts"]:
        run(["mountpoint", "-q", mount])
    repository = Path(destination["repositoryFile"]).read_text(encoding="utf-8").strip()
    if not repository:
        raise BackupError("Repository file is empty")
    # Restic accepts bare paths and an explicit local: backend, including
    # relative paths and paths containing colons. Match its local path forms.
    if ":" not in repository or re.match(
        r"^(?:local:|/|\\|\.\.[/\\]|[a-zA-Z]:[/\\])", repository
    ):
        # A missing external mount must never silently create/use a repository
        # on either source SSD. Source-backed bind mounts do not qualify.
        target = Path(repository.removeprefix("local:")).resolve()
        roots = [Path(path).resolve() for path in destination["requiredMounts"]]
        if not roots or not any(target.is_relative_to(root) for root in roots):
            raise BackupError(
                "Local repositories require an explicit external mount point"
            )
        source_devices = {
            run(["findmnt", "-n", "-o", "MAJ:MIN", "-T", path]).strip()
            for path in ("/", "/srv/data")
        }
        if (
            run(["findmnt", "-n", "-o", "MAJ:MIN", "-T", str(target)]).strip()
            in source_devices
        ):
            raise BackupError("A backup repository must not use a source filesystem")


def state_file(policy: dict[str, Any], name: str, phase: str) -> Path:
    """Locate a non-secret verification receipt.

    Returns:
        The validated or prepared file path.

    """
    return Path(policy["stateDirectory"]) / "checks" / f"{name}-{phase}.json"


def stamp(policy: dict[str, Any], name: str, phase: str) -> None:
    """Record a completed check without destroying the preceding receipt on failure."""
    target = state_file(policy, name, phase)
    target.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
    temporary = target.with_suffix(".tmp")
    temporary.write_text(
        json.dumps({"completed": time.time(), "phase": phase}) + "\n", encoding="utf-8"
    )
    temporary.chmod(0o644)
    temporary.replace(target)


def read_stamp(policy: dict[str, Any], name: str, phase: str) -> float:
    """Treat missing, malformed and future-dated receipts as unverified.

    Returns:
        The completion time, or zero when no valid result exists.

    """
    try:
        value = json.loads(state_file(policy, name, phase).read_text(encoding="utf-8"))[
            "completed"
        ]
        return float(value) if 0 < float(value) <= time.time() + 60 else 0
    except OSError, ValueError, TypeError, KeyError:
        return 0


def finish(policy: dict[str, Any], name: str, operation: str, result: str) -> None:
    """Keep a failed service result visible until that operation succeeds again."""
    stamp(
        policy, name, f"{operation}-{'success' if result == 'success' else 'failure'}"
    )


def policy_gaps(destinations: dict[str, Any]) -> list[str]:
    """Report incomplete declared topology without certifying physical properties.

    Returns:
        The actionable warnings.

    """
    gaps = []
    if len(destinations) < MINIMUM_BACKUP_COPIES:
        gaps.append(
            "Two independent backup destinations are required in addition to the working copy"
        )
    if (
        len({item["failureDomain"] for item in destinations.values()})
        < MINIMUM_BACKUP_COPIES
    ):
        gaps.append("Independent backup failure domains are not fully declared")
    if not any(
        item["medium"] not in {"ssd", "unknown"} for item in destinations.values()
    ):
        gaps.append("A second storage medium beyond the source SSDs is not declared")
    if not any(item["offsite"] for item in destinations.values()):
        gaps.append("An off-site backup is not declared")
    if not any(
        item["protection"] in {"offline", "immutable"} for item in destinations.values()
    ):
        gaps.append("An offline or externally immutable copy is not declared")
    return gaps


def status(policy: dict[str, Any], now: float | None = None) -> list[str]:
    """Report independent backup, integrity, restore and recovery-drill freshness.

    Returns:
        The actionable warnings.

    """
    now = time.time() if now is None else now
    messages = policy_gaps(policy["destinations"])
    for name, destination in policy["destinations"].items():
        phases = [
            ("backup", destination["maxAgeHours"] * 3600),
            ("integrity", destination["maxVerificationAgeDays"] * 86400),
            ("restore", destination["maxVerificationAgeDays"] * 86400),
            ("recovery-drill", 90 * 86400),
        ]
        if policy.get("coldRequired", True):
            phases.extend(
                (phase, destination.get("maxColdAgeDays", 14) * 86400)
                for phase in ("cold-backup", "cold-restore")
            )
        for phase, maximum in phases:
            completed = read_stamp(policy, name, phase)
            if not completed or now - completed > maximum:
                messages.append(f"{name}: {phase} is missing or overdue")
        for operation in ("backup", "verification", "cold", "database-backup"):
            failed = read_stamp(policy, name, f"{operation}-failure")
            if failed and failed >= read_stamp(policy, name, f"{operation}-success"):
                messages.append(f"{name}: latest {operation} attempt failed")
    return messages


def canary(policy: dict[str, Any]) -> Path:
    """Create a stable random file to prove a backup can be restored.

    Returns:
        The validated or prepared file path.

    """
    path = Path(policy["stateDirectory"]) / "restore-canary"
    path.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
    if not path.exists():
        # O_EXCL prevents replacing the expected value on repeated backups.
        with path.open("x", encoding="utf-8") as stream:
            stream.write(secrets.token_hex(512) + "\n")
        path.chmod(0o600)
    return path


def restore(policy: dict[str, Any], name: str, tag: str = "desktop-files") -> None:
    """Restore one canary into private temporary storage and compare its bytes.

    Raises:
        BackupError: A required security or recovery condition failed.

    """
    expected = canary(policy)
    snapshots = json.loads(
        run([
            "restic",
            "snapshots",
            "--json",
            "--tag",
            tag,
            "--latest",
            "1",
        ])
    )
    if len(snapshots) != 1:
        raise BackupError(
            "Expected one latest desktop-files snapshot; check repository scope"
        )
    # The service's private cache holds the probe, never a destination inside
    # live data. Always delete the plaintext probe after success or failure.
    cache = Path(os.environ.get("CACHE_DIRECTORY", "/var/cache"))
    with tempfile.TemporaryDirectory(
        prefix=f"desktop-restore-{name}-", dir=cache
    ) as directory:
        run([
            "restic",
            "restore",
            f"{snapshots[0]['id']}:{expected.parent}",
            "--target",
            directory,
            "--include",
            f"/{expected.name}",
            "--verify",
        ])
        # Restore the canary's own subtree, avoiding unrelated ancestor metadata
        # (for example root-owned /var) in an otherwise unprivileged probe.
        recovered = Path(directory) / expected.name
        if recovered.is_symlink() or recovered.read_bytes() != expected.read_bytes():
            raise BackupError("Restored canary did not match its source")


def cold_guard() -> None:
    """Require attended rescue mode without running user, container or VM workloads.

    No workloads are stopped automatically. This is a maintenance operation,
    not a live filesystem backup advertised as application-consistent.

    Raises:
        BackupError: The machine has not been quiesced for cold backup.

    """
    run(["systemctl", "is-active", "--quiet", "rescue.target"])
    units = run([
        "systemctl",
        "list-units",
        "--state=active,activating",
        "--no-legend",
        "--plain",
    ])
    if any(
        token.startswith("user@")
        or token in {"multi-user.target", "graphical-session.target"}
        for token in units.split()
    ):
        raise BackupError(
            "Stop user managers and leave multi-user mode before cold backup"
        )
    names = run(["ps", "-eo", "comm="]).splitlines()
    if any(
        name.strip().startswith((
            "qemu-system",
            "qemu-kvm",
            "dockerd",
            "containerd",
            "podman",
            "conmon",
            "runc",
        ))
        for name in names
    ):
        raise BackupError("Stop all VM and container processes before cold backup")
    run(["mountpoint", "-q", "/var/lib/libvirt/images"])


def cold_backup(policy: dict[str, Any], name: str) -> None:
    """Back up durable application trees while the operator keeps rescue mode quiescent."""
    guard(policy["destinations"][name])
    if policy.get("coldUnits"):
        native_cold_backup(policy, name)
        return
    cold_guard()
    expected = canary(policy)
    paths = [path for path in policy["coldPaths"] if Path(path).exists()]
    run(["restic", "backup", "--tag", "desktop-cold", *paths, str(expected)])
    cold_guard()
    stamp(policy, name, "cold-backup")
    restore(policy, name, "desktop-cold")
    stamp(policy, name, "cold-restore")


def native_journal(policy: dict[str, Any]) -> Path:
    """Locate the private, durable writer recovery record.

    Returns:
        The private operation journal path.

    """
    return Path(policy["stateDirectory"]) / "native-operation.json"


def native_recover(policy: dict[str, Any]) -> None:
    """Remove owned activation guards and resume every original writer.

    Raises:
        BackupError: An activation guard changed or an original writer could not restart.

    """
    journal = native_journal(policy)
    if not journal.exists():
        return
    record = json.loads(journal.read_text(encoding="utf-8"))
    for filename in record["guards"]:
        path = Path(filename)
        if path.exists() or path.is_symlink():
            if path.is_symlink() or path.read_text(encoding="utf-8") != record["body"]:
                raise BackupError(
                    "Native backup activation guard changed; recovery needs review"
                )
            path.unlink()
    run(["systemctl", "daemon-reload"])
    failed = []
    for unit in reversed(record["active"]):
        try:
            run(["systemctl", "start", unit])
            observed = run([
                "systemctl",
                "show",
                unit,
                "--property=ActiveState",
                "--value",
            ]).strip()
            if observed != "active":
                failed.append(unit)
        except OSError, subprocess.SubprocessError:
            failed.append(unit)
    if failed:
        raise BackupError("Native backup could not restart every original writer")
    journal.unlink()


def require_unmounted(path: str) -> None:
    """Refuse image capture while its filesystem is mounted.

    Raises:
        BackupError: The filesystem is still mounted.
        subprocess.CalledProcessError: Mount inspection failed.

    """
    try:
        run(["findmnt", "--noheadings", "--mountpoint", path])
    except subprocess.CalledProcessError as error:
        if error.returncode != 1:
            raise
    else:
        raise BackupError("Native backup image filesystem remains mounted")


def native_active_units(units: list[str]) -> list[str]:
    """Snapshot all writers before a stop can affect dependent units.

    Returns:
        Units that were active in the initial stable state.

    Raises:
        BackupError: A writer is missing, failed or transitioning.

    """
    active = []
    for unit in units:
        result = run(["systemctl", "show", unit, "--property=LoadState,ActiveState"])
        state = dict(line.split("=", 1) for line in result.splitlines())
        if state.get("LoadState") != "loaded" or state.get("ActiveState") not in {
            "active",
            "inactive",
        }:
            raise BackupError("Native backup writer is unavailable or transitioning")
        if state["ActiveState"] == "active":
            active.append(unit)
    return active


@contextlib.contextmanager
def native_quiesce(policy: dict[str, Any]) -> Generator[None]:
    """Guard activation and restore initial unit state on exit.

    Yields:
        A window with all declared writers stopped.

    Raises:
        BackupError: Writer state or guard ownership prevents a consistent capture.

    """
    journal = native_journal(policy)
    if journal.exists():
        raise BackupError("An interrupted native backup requires recovery first")
    units = policy["coldUnits"]
    if (
        not units
        or len(set(units)) != len(units)
        or any(
            not re.fullmatch(r"[a-zA-Z0-9@_.:-]+\.(?:service|mount|timer|socket)", unit)
            for unit in units
        )
    ):
        raise BackupError("Native backup units are invalid")
    guards = [
        Path(policy.get("nativeGuardDirectory", "/run/systemd/system.control"))
        / (unit + ".d")
        / "90-desktop-native-backup.conf"
        for unit in units
    ]
    if any(path.exists() or path.is_symlink() for path in guards):
        raise BackupError("Native backup activation guard already exists")
    active = native_active_units(units)
    body = f"[Unit]\nConditionPathExists=!{journal}\n"
    journal.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=journal.parent, delete=False
    ) as stream:
        temporary = Path(stream.name)
        json.dump(
            {"active": active, "guards": [str(path) for path in guards], "body": body},
            stream,
        )
        stream.flush()
        os.fsync(stream.fileno())
    try:
        os.link(temporary, journal)
    finally:
        temporary.unlink()
    try:
        for path in guards:
            path.parent.mkdir(parents=True, exist_ok=True)
            with path.open("x", encoding="utf-8") as stream:
                stream.write(body)
        run(["systemctl", "daemon-reload"])
        run(["systemctl", "stop", *units])
        for unit in units:
            state = run([
                "systemctl",
                "show",
                unit,
                "--property=ActiveState",
                "--value",
            ]).strip()
            if state != "inactive":
                raise BackupError("Native backup writer did not stop")
        for path in policy.get("coldUnmounts", []):
            require_unmounted(path)
        yield
    finally:
        native_recover(policy)


def file_manifest(paths: list[str], root: Path | None = None) -> dict[str, Any]:
    """Hash regular files and preserve symlinks without following them.

    Returns:
        Content and metadata indexed by source paths.

    Raises:
        BackupError: A source is missing, redirected or an unsupported file type.

    """
    result = {}
    for name in paths:
        original = Path(name)
        path = original if root is None else root / str(original).lstrip("/")
        if not path.exists() and not path.is_symlink():
            raise BackupError("A required native backup path is missing")
        if path.is_symlink():
            raise BackupError("Native backup roots must not be symlinks")
        entries = [path, *sorted(path.rglob("*"))] if path.is_dir() else [path]
        for entry in entries:
            key = str(original / entry.relative_to(path))
            info = entry.lstat()
            item = {
                "mode": stat.S_IMODE(info.st_mode),
                "uid": info.st_uid,
                "gid": info.st_gid,
            }
            if stat.S_ISLNK(info.st_mode):
                item["symlink"] = str(entry.readlink())
            elif stat.S_ISREG(info.st_mode):
                with entry.open("rb") as stream:
                    item["sha256"] = hashlib.file_digest(stream, "sha256").hexdigest()
            elif not stat.S_ISDIR(info.st_mode):
                raise BackupError("Native backup contains an unsupported file type")
            result[key] = item
    return result


def native_cold_backup(policy: dict[str, Any], name: str) -> None:
    """Capture native applications and verify a full isolated restore.

    Raises:
        BackupError: Source stability or full restoration could not be verified.

    """
    with Path(policy.get("bulkLock", "/run/workstation-workloads/bulk.lock")).open(
        "a", encoding="utf-8"
    ) as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        with native_quiesce(policy):
            if policy.get("coldPrepareCommand"):
                run(policy["coldPrepareCommand"])
            paths = policy["coldPaths"]
            # Missing optional legacy directories are allowed; configured native
            # application paths must exist and may not silently lose coverage.
            expected = file_manifest(paths)
            output = run([
                policy["coldRestic"],
                "backup",
                "--json",
                "--tag",
                "desktop-cold",
                *paths,
            ])
            summaries = [json.loads(line) for line in output.splitlines()]
            snapshot = next(
                item["snapshot_id"]
                for item in summaries
                if item.get("message_type") == "summary"
            )
            if file_manifest(paths) != expected:
                raise BackupError(
                    "Native source changed while its writers were stopped"
                )
        stamp(policy, name, "cold-backup")
        cache = Path(os.environ.get("CACHE_DIRECTORY", "/var/cache"))
        with tempfile.TemporaryDirectory(
            prefix="native-restore-", dir=cache
        ) as temporary:
            # Restore each managed subtree without importing unrelated ancestor
            # metadata (including root-owned /var or /tmp in portable probes).
            for source_name in paths:
                path = Path(source_name)
                target = Path(temporary) / str(path.parent).lstrip("/")
                target.mkdir(parents=True, exist_ok=True)
                run([
                    policy["coldRestic"],
                    "restore",
                    f"{snapshot}:{path.parent}",
                    "--target",
                    str(target),
                    "--include",
                    f"/{path.name}",
                    "--verify",
                ])
            if file_manifest(paths, Path(temporary)) != expected:
                raise BackupError(
                    "Native application restore did not match captured files"
                )
        receipt = state_file(policy, name, "native-restore")
        receipt.write_text(
            json.dumps({
                "completed": time.time(),
                "snapshot": snapshot,
                "filesVerified": sum(
                    "sha256" in item or "symlink" in item for item in expected.values()
                ),
                "scope": "full-native-cold-paths",
            })
            + "\n",
            encoding="utf-8",
        )
        receipt.chmod(0o600)
        stamp(policy, name, "cold-restore")


def main() -> int:  # ruff: ignore[complex-structure, too-many-branches] - explicit CLI operations have different privilege gates
    """Dispatch the operator and systemd interfaces.

    Returns:
        The command exit status.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("policy", type=Path)
    parser.add_argument(
        "action",
        nargs="?",
        default="status",
        choices=[
            "status",
            "guard",
            "stamp",
            "finish",
            "canary",
            "restore",
            "cold-backup",
            "recover-native",
            "record-recovery-drill",
        ],
    )
    parser.add_argument("name", nargs="?")
    parser.add_argument("phase", nargs="?", choices=[*PHASES, "verification", "cold"])
    args = parser.parse_args()
    policy = json.loads(args.policy.read_text(encoding="utf-8"))
    if args.action == "status":
        messages = status(policy)
        print("3-2-1-1-0 backup status")
        print(
            "\n".join(f"- {message}" for message in messages)
            if messages
            else "Declared topology and recorded checks are current."
        )
        print(
            "Physical independence, off-site location and immutability require external verification."
        )
        print(
            "Automated restore covers a canary; application recovery requires a separate drill."
        )
        return 1 if messages else 0
    if os.geteuid() != 0:
        parser.error("This operation requires root")
    if (
        args.action not in {"canary", "recover-native"}
        and args.name not in policy["destinations"]
    ):
        parser.error("Unknown backup destination")
    if args.action == "guard":
        guard(policy["destinations"][args.name])
    elif args.action == "stamp":
        if args.phase not in PHASES:
            parser.error("stamp requires a phase")
        stamp(policy, args.name, args.phase)
    elif args.action == "finish":
        if args.phase not in {"backup", "verification", "cold", "database-backup"}:
            parser.error("finish requires an operation")
        finish(
            policy, args.name, args.phase, os.environ.get("SERVICE_RESULT", "unknown")
        )
    elif args.action == "canary":
        canary(policy)
    elif args.action == "restore":
        restore(policy, args.name)
    elif args.action == "cold-backup":
        cold_backup(policy, args.name)
    elif args.action == "recover-native":
        native_recover(policy)
    elif args.action == "record-recovery-drill":
        answer = input(
            "After restoring real files and testing application recovery independently, type 'recovery tested': "
        )
        if answer != "recovery tested":
            parser.error("Recovery drill was not confirmed")
        stamp(policy, args.name, "recovery-drill")
    return 0


if __name__ == "__main__":

    def interrupted(_signal: int, _frame: object) -> None:
        """Turn cancellation into normal maintenance failure and cleanup.

        Raises:
            BackupError: Backup cancellation was requested.

        """
        raise BackupError("Backup operation interrupted")

    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        # Never echo subprocess output: provider errors can contain credentials.
        print(
            str(error)
            if isinstance(error, BackupError)
            else f"Backup operation failed: {type(error).__name__}. Inspect the configured repository and service.",
            file=__import__("sys").stderr,
        )
        raise SystemExit(1) from None
