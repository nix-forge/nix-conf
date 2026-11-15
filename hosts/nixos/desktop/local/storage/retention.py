"""Retire reviewed OS profile generations while preserving explicit recovery roots."""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import operator
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from typing import Any

DAY = 24 * 60 * 60


def recovery_identity(target: str) -> str:
    """Recognize activatable wrappers that share the underlying system bin tree.

    Returns:
        A conservative identity shared by a wrapper and its bootable system.

    """
    binary_tree = Path(target) / "bin"
    return str(binary_tree.resolve(strict=True)) if binary_tree.exists() else target


def external_system_pins(cfg: dict[str, Any]) -> set[str]:
    """Preserve explicitly rooted systems without protecting every managed generation.

    Returns:
        System targets rooted outside this managed system profile.

    """
    if not cfg.get("nixStore"):
        return set()
    result = subprocess.run(
        [cfg["nixStore"], "--gc", "--print-roots"],
        capture_output=True,
        text=True,
        check=True,
    )
    protected = set()
    profile = cfg["profile"]
    for line in result.stdout.splitlines():
        root, target = line.rsplit(" -> ", 1)
        root = json.loads(root) if root.startswith('"') else root
        if root == profile or re.fullmatch(re.escape(profile) + r"-\d+-link", root):
            continue
        if "nixos-system-" in Path(target).name:
            protected.add(target)
    return protected


def plan(policy: dict[str, Any], now: float | None = None) -> dict[str, Any]:
    """Inventory a system profile without touching any generation or task root.

    Returns:
        Exact candidates and a fingerprint binding all recovery observations.

    Raises:
        ValueError: The active profile and running system disagree.

    """
    cfg = policy["generations"]
    profile = Path(cfg["profile"])
    current = str(Path(cfg["currentSystem"]).resolve(strict=True))
    booted = str(Path(cfg["bootedSystem"]).resolve(strict=True))
    # Activation wrappers retain a distinct profile path while exposing the
    # running system's bin tree. Compare the same identity used to protect
    # recovery generations, while still refusing an actual pending switch.
    if recovery_identity(str(profile.resolve(strict=True))) != recovery_identity(
        current
    ):
        raise ValueError(
            "System activation is not settled; refusing generation retirement"
        )
    protected = {current, booted} | external_system_pins(cfg)
    pins = Path(cfg["pinsDirectory"])
    if pins.exists():
        protected.update(
            str(path.resolve(strict=True))
            for path in pins.iterdir()
            if path.is_symlink()
        )
    protected_identities = {recovery_identity(target) for target in protected}
    generations = []
    for path in profile.parent.glob(f"{profile.name}-*-link"):
        match = re.fullmatch(re.escape(profile.name) + r"-(\d+)-link", path.name)
        if not match or not path.is_symlink():
            raise ValueError("Unexpected system generation entry")
        target = str(path.resolve(strict=True))
        if not target.startswith(cfg["storeDirectory"].rstrip("/") + "/"):
            raise ValueError("System generation is not an immutable store path")
        generations.append({
            "number": int(match[1]),
            "target": target,
            "recoveryIdentity": recovery_identity(target),
            "modified": path.lstat().st_mtime,
        })
    generations.sort(key=operator.itemgetter("number"), reverse=True)
    cutoff = (time.time() if now is None else now) - cfg["keepDays"] * DAY
    recent = {item["number"] for item in generations[: cfg["keepCount"]]}
    candidates = [
        item["number"]
        for item in generations
        if item["number"] not in recent
        and item["modified"] < cutoff
        and item["target"] not in protected
        and item["recoveryIdentity"] not in protected_identities
    ]
    output = {
        "profile": str(profile),
        "generations": generations,
        "protectedTargets": sorted(protected),
        "candidates": candidates,
    }
    output["fingerprint"] = hashlib.sha256(
        json.dumps(output, sort_keys=True).encode()
    ).hexdigest()
    return output


def apply(policy: dict[str, Any], reviewed: dict[str, Any]) -> dict[str, Any]:
    """Recheck a reviewed plan after taking the existing workload reservation.

    Returns:
        The exact retirement result, retaining every protected generation.

    Raises:
        ValueError: Source/profile observations changed after review.

    """
    with Path(policy["bulkLock"]).open("r+", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        current = plan(policy)
        if current["fingerprint"] != reviewed["fingerprint"]:
            raise ValueError("Generation plan changed; review a fresh plan")
        cfg = policy["generations"]
        pins = Path(cfg["pinsDirectory"])
        pins.mkdir(parents=True, mode=0o700, exist_ok=True)
        target = str(Path(cfg["bootedSystem"]).resolve(strict=True))
        temporary = pins / ".last-booted.tmp"
        temporary.unlink(missing_ok=True)
        temporary.symlink_to(target)
        temporary.replace(pins / "last-booted")
        if current["candidates"]:
            subprocess.run(
                [
                    cfg["nixEnv"],
                    "--profile",
                    cfg["profile"],
                    "--delete-generations",
                    *map(str, current["candidates"]),
                ],
                check=True,
            )
        return {"completed": time.time(), "plan": current, "status": "retired"}


def save(path: Path, value: dict[str, Any]) -> None:
    """Save a root-owned plan or receipt without publishing private paths."""
    temporary = path.with_suffix(".tmp")
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
        json.dump(value, stream)
        stream.flush()
        os.fsync(stream.fileno())
    temporary.replace(path)


def main() -> int:
    """Generate a plan, apply an exact reviewed plan, or run the configured policy.

    Returns:
        Zero for a successful finite operation, nonzero for refusal or failure.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--policy", type=Path, required=True)
    parser.add_argument("command", choices=["plan", "apply", "retire"])
    parser.add_argument("--plan", type=Path)
    args = parser.parse_args()
    try:
        policy = json.loads(args.policy.read_text(encoding="utf-8"))
        return execute(policy, args)
    except (
        OSError,
        ValueError,
        KeyError,
        TypeError,
        subprocess.SubprocessError,
    ) as error:
        print(f"Generation retirement refused: {error}", file=sys.stderr)
        return 1


def execute(policy: dict[str, Any], args: argparse.Namespace) -> int:
    """Bind native retirement to either explicit review or the configured policy.

    Returns:
        Zero after persisting the reviewed result.

    Raises:
        ValueError: Applying a plan requires an explicit plan path.

    """
    current = plan(policy)
    state = Path(policy["stateDirectory"])
    if args.command == "plan":
        save(state / "generation-plan.json", current)
        print(json.dumps(current))
        return 0
    if args.command == "apply":
        if args.plan is None:
            raise ValueError("Supply the exact reviewed --plan file")
        current = json.loads(args.plan.read_text(encoding="utf-8"))
    result = apply(policy, current)
    save(state / "generation-retirement.json", result)
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
