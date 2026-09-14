"""Run declared application exports and isolated restoration drills."""

# ruff: file-ignore[print, subprocess-without-shell-equals-true, suspicious-subprocess-import, raise-vanilla-args, raw-string-in-exception, start-process-with-partial-path, try-except-in-loop]
# Operator CLI invokes immutable declared commands without shell interpolation.
from __future__ import annotations

import argparse
import contextlib
import fcntl
import hashlib
import json
import os
import signal
import subprocess
import tempfile
import time
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from typing import Any


class RecoveryError(RuntimeError):
    """A recovery phase failed; the preceding success remains separate evidence."""


def command(arguments: list[str], environment: dict[str, str], timeout: int) -> None:
    """Execute a declared hook with private output in the service journal.

    Raises:
        subprocess.CalledProcessError: The hook returned a failing exit status.
        RecoveryError: The hook left unfinished child processes.

    """
    with subprocess.Popen(
        arguments, env=environment, start_new_session=True
    ) as process:
        try:
            result = process.wait(timeout=timeout)
            if result:
                raise subprocess.CalledProcessError(result, arguments)
            try:
                os.killpg(process.pid, 0)
            except ProcessLookupError:
                return
            raise RecoveryError("Recovery hook left unfinished child processes")
        finally:
            # Include grandchildren left by timed-out shell hooks. Cleanup must
            # finish before writers restart or temporary exports disappear.
            with contextlib.suppress(ProcessLookupError):
                os.killpg(process.pid, signal.SIGKILL)
            process.wait()


def receipt(directory: Path, action: str, result: str, policy: dict[str, Any]) -> None:
    """Publish the last attempt separately from the most recent successful one."""
    record = {
        "completed": time.time(),
        "action": action,
        "result": result,
        "policySha256": hashlib.sha256(
            json.dumps(policy, sort_keys=True).encode()
        ).hexdigest(),
        "scope": "isolated-application-drill"
        if action == "drill"
        else "application-backup",
    }
    for name in [
        f"{action}-attempt",
        *([f"{action}-success"] if result == "success" else []),
    ]:
        temporary = directory / f"{name}.tmp"
        temporary.write_text(json.dumps(record) + "\n")
        temporary.chmod(0o600)
        temporary.replace(directory / f"{name}.json")


def backup(policy: dict[str, Any], environment: dict[str, str]) -> None:
    """Stop only running declared writers and resume all of them after any failure.

    Raises:
        RecoveryError: A writer could not resume, including after another failure.

    """
    restart = []
    active = []
    failed = []
    timeout = policy["timeoutSeconds"]
    try:
        for unit in policy["units"]:
            result = subprocess.run(
                ["systemctl", "show", unit, "--property=LoadState,ActiveState"],
                capture_output=True,
                text=True,
                check=True,
                timeout=timeout,
            )
            state = dict(line.split("=", 1) for line in result.stdout.splitlines())
            if state.get("LoadState") != "loaded" or state.get("ActiveState") not in {
                "active",
                "inactive",
            }:
                raise RecoveryError(
                    "Writer state is unavailable, failed or transitioning"
                )
            if state["ActiveState"] == "active":
                active.append(unit)
        # Stopping one unit can also stop another declared writer through
        # PartOf/BindsTo. Snapshot every state before the first mutation and
        # resume the entire initial set even if the first stop fails.
        restart = active
        for unit in active:
            command(["systemctl", "stop", unit], environment, timeout)
        command(policy["export"], environment, timeout)
        command(policy["backup"], environment, timeout)
    finally:
        for unit in reversed(restart):
            try:
                command(["systemctl", "start", unit], environment, timeout)
            except (OSError, subprocess.SubprocessError, RecoveryError):
                failed.append(unit)
        if failed:
            raise RecoveryError("One or more application writers could not restart")


def execute(policy: dict[str, Any], action: str) -> None:
    """Serialize each application and keep all drill writes in fresh private scratch.

    Raises:
        RecoveryError: Another backup or drill for this application is running.

    """
    directory = Path(policy["stateDirectory"])
    directory.mkdir(parents=True, mode=0o700, exist_ok=True)
    with (directory / "operation.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RecoveryError(
                "An application recovery operation is already running"
            ) from error
        try:  # ruff: ignore[too-many-statements-in-try-clause] - record failure across all phases and cleanup
            with tempfile.TemporaryDirectory(
                prefix="operation-", dir=directory
            ) as scratch:
                export = Path(scratch) / "export"
                target = Path(scratch) / "target"
                export.mkdir(mode=0o700)
                target.mkdir(mode=0o700)
                environment = dict(
                    os.environ, RECOVERY_EXPORT=str(export), RECOVERY_TARGET=str(target)
                )
                if action == "backup":
                    backup(policy, environment)
                else:
                    for phase in ("recover", "restore", "check"):
                        command(policy[phase], environment, policy["timeoutSeconds"])
            receipt(directory, action, "success", policy)
        except BaseException:
            receipt(directory, action, "failure", policy)
            raise


def main() -> int:
    """Dispatch an application backup or a disposable recovery drill.

    Returns:
        Zero after all phases complete, otherwise one.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("policy", type=Path)
    parser.add_argument("action", choices=["backup", "drill"])
    args = parser.parse_args()

    def interrupted(_signal: int, _frame: object) -> None:
        raise RecoveryError("Recovery operation interrupted")

    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    try:
        execute(json.loads(args.policy.read_text()), args.action)
    except (OSError, ValueError, RecoveryError, subprocess.SubprocessError) as error:
        print(f"Application recovery failed: {type(error).__name__}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
