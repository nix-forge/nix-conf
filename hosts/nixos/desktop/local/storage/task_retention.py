"""Release only completed task-owned job roots; preserve source and result records."""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
import pwd
import re
import shutil
import stat
import subprocess
import sys
import time
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from typing import Any, Never

ROOT_NAMES = ("executor-root", "configuration-root")
SUBVOLUME_INODE = 256


def inspect_job(command: str, identifier: str) -> dict[str, Any]:
    """Use the queue's existing native/receipt reconciliation contract.

    Returns:
        The one stable job's current public status.

    Raises:
        ValueError: The requested job cannot be identified unambiguously.

    """
    result = subprocess.run(
        [command, "status", identifier], capture_output=True, text=True, check=True
    )
    records = json.loads(result.stdout)["jobs"]
    if len(records) != 1 or records[0]["id"] != identifier:
        raise ValueError("Job status is ambiguous")
    return records[0]


def retirement_plan(state: Path, owner: str, command: str) -> list[dict[str, Any]]:
    """Refuse retirement of an owner with unfinished or unresolved executions.

    Returns:
        Exact owned directories and their durable evidence hashes.

    Raises:
        ValueError: A job is not terminal/drained or a root is unexpected.

    """
    planned = []
    for directory in (state / "jobs").iterdir():
        if directory.is_symlink() or not re.fullmatch(r"[0-9a-f]{32}", directory.name):
            raise ValueError("Unexpected job state directory")
        recipe_file = directory / "recipe.json"
        # An aborted submission can leave an empty directory. The caller holds
        # submit.lock, so it cannot be a currently assembling job. Preserve it;
        # any unidentified nonempty state remains a refusal.
        if not recipe_file.exists() and not any(directory.iterdir()):
            continue
        recipe = json.loads(recipe_file.read_text(encoding="utf-8"))
        if recipe["owner"] != owner:
            continue
        record = inspect_job(command, directory.name)
        receipt = record.get("receipt") or {}
        native = record.get("nativeStatus")
        terminal = isinstance(native, dict) and "Done" in native
        cancelled = (
            receipt.get("phase") == "cancelled-before-start"
            and isinstance(native, dict)
            and "Stashed" in native
        )
        if (
            not (terminal or cancelled)
            or receipt.get("drained") is not True
            or receipt.get("exitCode") is None
        ):
            raise ValueError(
                "Task has queued, running or unresolved jobs; preserve their roots"
            )
        roots = []
        for name in ROOT_NAMES:
            path = directory / name
            if path.is_symlink():
                if not re.fullmatch(
                    r"/nix/store/[a-z0-9]{32}-[^/]+", str(path.readlink())
                ):
                    raise ValueError("Job root has an unexpected target")
                roots.append(str(path))
            elif path.exists():
                raise ValueError("Refusing to remove a non-symlink job root")
        planned.append({
            "id": directory.name,
            "roots": roots,
            "recipeSha256": hashlib.sha256(recipe_file.read_bytes()).hexdigest(),
            "resultSha256": hashlib.sha256(
                (directory / "result.json").read_bytes()
            ).hexdigest(),
        })
    return planned


def retire(
    state: Path,
    owner: str,
    command: str,
    preserved: Path | None,
    cache_root: Path | None = None,
) -> dict[str, Any]:
    """Release roots only after explicit task completion and result preservation.

    Returns:
        The review plan or an idempotent root-release receipt.

    """
    with (state / "submit.lock").open("a", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        planned = retirement_plan(state, owner, command)
        result: dict[str, Any] = {"owner": owner, "jobs": planned, "released": False}
        if preserved is None:
            return result
        with preserved.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        result.update({
            "completed": time.time(),
            "preservedResult": str(preserved.resolve(strict=True)),
            "preservedSha256": digest,
            "released": False,
        })
        if cache_root is not None:
            prepare_cache_removal(cache_root, owner, preserved)
        # Persist completion evidence before unlinking anything. Interrupted
        # cleanup can be resumed; recipes, results, claims and native state stay.
        record = state / (
            "retired-task-" + hashlib.sha256(owner.encode()).hexdigest() + ".json"
        )
        temporary = record.with_suffix(".tmp")
        descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            json.dump(result, stream)
            stream.flush()
            os.fsync(stream.fileno())
        temporary.replace(record)
        for job in planned:
            for path in job["roots"]:
                Path(path).unlink()
        if cache_root is not None:
            remove_cache(cache_root, owner, preserved)
        result["released"] = True
        temporary.write_text(json.dumps(result), encoding="utf-8")
        temporary.chmod(0o600)
        temporary.replace(record)
        return result


def verify_cache_root(root: Path) -> None:
    """Require the root-provisioned snapshot boundary on the mounted data SSD.

    Raises:
        ValueError: Cache placement would use an unverified or fallback path.
        FileNotFoundError: Mount inspection is unavailable.

    """
    findmnt = shutil.which("findmnt")
    if findmnt is None:
        raise FileNotFoundError("Mount inspection is unavailable")
    if (
        root.is_symlink()
        or root.stat().st_uid != 0
        or root.stat().st_ino != SUBVOLUME_INODE
    ):
        raise ValueError("Task cache root is not the provisioned subvolume")
    mounts = []
    for path in (Path("/srv/data"), root):
        result = subprocess.run(
            [findmnt, "--json", "--target", str(path), "--output", "UUID,TARGET"],
            capture_output=True,
            text=True,
            check=True,
        )
        mounts.append(json.loads(result.stdout)["filesystems"][0])
    if (
        mounts[0]["target"] != "/srv/data"
        or not mounts[0]["uuid"]
        or mounts[0]["uuid"] != mounts[1]["uuid"]
    ):
        raise ValueError("Task cache data mount is unavailable")


def cache_location(root: Path, owner: str) -> tuple[Path, Path]:
    """Constrain caches to the caller's root-provisioned private namespace.

    Returns:
        The cache and its sibling ownership marker.

    Raises:
        ValueError: The owner or provisioned namespace is invalid.

    """
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,63}", owner):
        raise ValueError(
            "Cache owner must be one safe task identifier of at most 64 characters"
        )
    verify_cache_root(root)
    namespace = root / pwd.getpwuid(os.getuid()).pw_name
    if namespace.is_symlink() or namespace.stat().st_uid != os.getuid():
        raise ValueError("Task cache user namespace has unexpected ownership")
    target = namespace / owner
    if target.is_symlink():
        raise ValueError("Task cache cannot be a symlink")
    return target, namespace / (owner + ".owner.json")


def create_cache(root: Path, owner: str) -> Path:
    """Create or reuse explicitly regenerable task data, never source/results.

    Returns:
        The private snapshot-excluded cache path.

    Raises:
        ValueError: An existing path is not an owned task cache.

    """
    target, marker = cache_location(root, owner)
    identity = {"owner": owner, "uid": os.getuid()}
    if target.exists():
        if (
            not marker.exists()
            or json.loads(marker.read_text(encoding="utf-8")) != identity
        ):
            raise ValueError("Existing directory is not an owned task cache")
        return target
    target.mkdir(mode=0o700)
    marker.write_text(json.dumps(identity), encoding="utf-8")
    marker.chmod(0o600)
    return target


def cache_walk_error(error: OSError) -> Never:
    """Refuse cleanup when a subtree cannot be inspected."""
    raise error


def prepare_cache_removal(root: Path, owner: str, preserved: Path) -> None:
    """Remove only an explicitly completed cache with preserved external results.

    Raises:
        ValueError: Evidence or another mount would be endangered by cleanup.

    """
    target, marker = cache_location(root, owner)
    if not target.exists():
        return
    if json.loads(marker.read_text(encoding="utf-8")) != {
        "owner": owner,
        "uid": os.getuid(),
    }:
        raise ValueError("Task cache ownership does not match completion")
    if preserved.resolve(strict=True).is_relative_to(
        target
    ) or Path.cwd().resolve().is_relative_to(target):
        raise ValueError(
            "Move results and the current directory outside the cache before retirement"
        )
    for line in Path("/proc/self/mountinfo").read_text(encoding="utf-8").splitlines():
        point = re.sub(
            r"\\([0-7]{3})", lambda match: chr(int(match[1], 8)), line.split()[4]
        )
        if Path(point).is_relative_to(target):
            raise ValueError("Nested mount prevents task cache retirement")
    for base, directories, _ in os.walk(
        target, followlinks=False, onerror=cache_walk_error
    ):
        if Path(base).stat().st_uid != os.getuid():
            raise ValueError(
                "Task cache contains a directory owned by another identity"
            )
        for name in directories:
            child = Path(base) / name
            if not child.is_symlink() and child.stat().st_ino == SUBVOLUME_INODE:
                raise ValueError("Nested subvolume prevents task cache retirement")


def remove_cache(root: Path, owner: str, preserved: Path) -> None:
    """Recheck the owned tree immediately before explicit finite removal."""
    prepare_cache_removal(root, owner, preserved)
    target, marker = cache_location(root, owner)
    if target.exists():
        # Build outputs often have read-only directories. The complete tree
        # was inspected above; grant only its owner the permissions needed to
        # retire it. Never follow links or change ownership.
        for base, _, _ in os.walk(target, followlinks=False, onerror=cache_walk_error):
            mode = Path(base).lstat().st_mode
            Path(base).chmod(stat.S_IMODE(mode) | stat.S_IRWXU, follow_symlinks=False)
        shutil.rmtree(target)
        marker.unlink()


def main() -> int:
    """Keep retirement opt-in; age and job success never imply task completion.

    Returns:
        Zero for a completed review/release, nonzero for a refusal.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--state",
        type=Path,
        default=Path(
            os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))
        )
        / "workstation-jobs",
    )
    parser.add_argument("--owner", required=True)
    parser.add_argument(
        "--cache-root", type=Path, default=Path("/srv/data/work/scratch")
    )
    parser.add_argument(
        "--create-cache",
        action="store_true",
        help="Create regenerable data only; preserve source and results elsewhere",
    )
    parser.add_argument("--remove-cache", action="store_true")
    parser.add_argument("--complete-task", action="store_true")
    parser.add_argument("--preserved-result", type=Path)
    args = parser.parse_args()
    if args.complete_task != (args.preserved_result is not None):
        parser.error(
            "Root release requires both --complete-task and --preserved-result"
        )
    if args.create_cache:
        if args.complete_task or args.remove_cache:
            parser.error("Cache creation cannot also finalize a task")
        try:
            print(create_cache(args.cache_root, args.owner))
        except (
            OSError,
            ValueError,
            KeyError,
            TypeError,
            subprocess.SubprocessError,
        ) as error:
            print(f"Task cache refused: {error}", file=sys.stderr)
            return 1
        return 0
    if args.remove_cache and not args.complete_task:
        parser.error("Cache removal requires explicit task completion")
    command = shutil.which("workstation-job")
    if command is None:
        parser.error("workstation-job is unavailable")
    try:
        result = retire(
            args.state,
            args.owner,
            command,
            args.preserved_result,
            args.cache_root if args.remove_cache else None,
        )
    except (
        OSError,
        ValueError,
        KeyError,
        TypeError,
        subprocess.SubprocessError,
    ) as error:
        print(f"Task root retirement refused: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
