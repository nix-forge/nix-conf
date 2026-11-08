"""Build Nix packages inside a bounded allocation using a private writable store."""

from __future__ import annotations

import argparse
import contextlib
import fcntl
import json
import os
import signal
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Execute the configured Nix binary without a shell.
import sys
import uuid
from pathlib import Path
from typing import TYPE_CHECKING, Any
from urllib.parse import quote

if TYPE_CHECKING:
    from collections.abc import Generator
    from types import FrameType

GIB = 1024**3


def allocation(memory_gib: int, maximum_gib: int | None = None) -> bool:
    """Verify an existing bounded scope, refusing to resize a running job.

    Returns:
        Whether the caller already has the requested isolated allocation.

    Raises:
        ValueError: An outer workload has a different budget or lacks isolation.

    """
    group = (
        Path("/proc/self/cgroup").read_text(encoding="utf-8").strip().split("::", 1)[1]
    )
    if "/background-workload.slice/" not in group:
        return False
    root = Path("/sys/fs/cgroup") / group.lstrip("/")
    maximum = (root / "memory.max").read_text().strip()
    if (
        not maximum.isdigit()
        or not memory_gib * GIB <= int(maximum) <= (maximum_gib or memory_gib) * GIB
        or (root / "memory.swap.max").read_text().strip() != "0"
        or not os.statvfs("/nix/store").f_flag & os.ST_RDONLY
        or Path("/nix/var/nix/daemon-socket/socket").exists()
    ):
        msg = "Select the matching bounded memory budget on the outermost invocation"
        raise ValueError(msg)
    return True


def write_receipt(path: Path, value: dict[str, Any]) -> None:
    """Replace one private receipt atomically without removing earlier attempts."""
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def reconcile(state: Path) -> None:
    """Mark abandoned attempts uncertain after obtaining their exclusive lock."""
    for path in state.glob("attempts/*/receipt.json"):
        receipt = json.loads(path.read_text(encoding="utf-8"))
        if receipt["status"] == "running":
            receipt.update(status="interrupted", termination="unknown", exitCode=None)
            write_receipt(path, receipt)


def terminate(signum: int, _frame: FrameType | None) -> None:
    """Translate catchable cancellation into the ordinary receipt cleanup path.

    Raises:
        SystemExit: The conventional signal exit status.

    """
    raise SystemExit(128 + signum)


@contextlib.contextmanager
def cancellation_signals() -> Generator[None]:
    """Restore signal handlers after recording a cancelled attempt.

    Yields:
        An interval where catchable signals unwind Python cleanup.

    """
    previous = {
        number: signal.signal(number, terminate)
        for number in [signal.SIGINT, signal.SIGTERM, signal.SIGHUP]
    }
    try:
        yield
    finally:
        for number, handler in previous.items():
            signal.signal(number, handler)


def completion(result: subprocess.CompletedProcess, store: Path) -> dict[str, Any]:
    """Translate Nix's successful logical outputs to usable private-store paths.

    Returns:
        Build identities and output paths, or the original failed status.

    """
    value: dict[str, Any] = {
        "exitCode": result.returncode,
        "status": "succeeded" if result.returncode == 0 else "failed",
    }
    if result.returncode == 0:
        value["builds"] = json.loads(result.stdout)
        value["physicalOutputs"] = [
            str(store / output.lstrip("/"))
            for item in value["builds"]
            for output in item["outputs"].values()
        ]
    return value


def build(args: argparse.Namespace, runtime: dict[str, Any]) -> int:
    """Run the actual Nix build and retain roots, identities and physical outputs.

    Returns:
        The build's exit status; failed builds remain failed attempts.

    """
    state = args.state.resolve()
    state.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (state / "lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        reconcile(state)
        attempt = state / "attempts" / uuid.uuid4().hex
        attempt.mkdir(mode=0o700, parents=True)
        store = state / "store"
        command = [
            runtime["nix"],
            "--extra-experimental-features",
            "nix-command flakes",
            "build",
            "--store",
            "local?root=" + quote(str(store), safe="/"),
            "--option",
            "build-users-group",
            "",
            "--option",
            "builders",
            "",
            "--option",
            "sandbox",
            "true",
            "--max-jobs",
            str(runtime["maxJobs"]),
            "--cores",
            str(runtime["cores"]),
            "--out-link",
            str(attempt / "result"),
            "--json",
        ]
        if args.impure:
            command.append("--impure")
        if args.file:
            command.extend(["--file", str(args.file.resolve())])
        command.extend(args.installables)
        receipt: dict[str, Any] = {
            "status": "running",
            "memoryGiB": args.memory_gib,
            "store": str(store),
            "command": command,
        }
        if getattr(args, "memory_max_gib", None) is not None:
            receipt["memoryRangeGiB"] = {
                "minimum": args.memory_gib,
                "maximum": args.memory_max_gib,
            }
            group = (
                Path("/proc/self/cgroup")
                .read_text(encoding="utf-8")
                .strip()
                .split("::", 1)[1]
            )
            receipt["initialMemoryMaxBytes"] = int(
                (Path("/sys/fs/cgroup") / group.lstrip("/") / "memory.max").read_text()
            )
        path = attempt / "receipt.json"
        write_receipt(path, receipt)
        try:
            with cancellation_signals():
                result = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Fixed Nix executable and argv; retain ownership while the Nix client is alive.
                    command,
                    stdout=subprocess.PIPE,
                    pass_fds=(lock.fileno(),),
                    check=False,
                )
            receipt.update(completion(result, store))
        except BaseException:
            receipt["status"] = "interrupted"
            write_receipt(path, receipt)
            raise
        write_receipt(path, receipt)
        sys.stdout.write(json.dumps({"receipt": str(path), **receipt}) + "\n")
        return result.returncode


def main() -> int:
    """Enter the bounded runner before evaluating or building any Nix inputs.

    Returns:
        The build status, or a configuration error without launching a build.

    """
    bootstrap = argparse.ArgumentParser(add_help=False)
    bootstrap.add_argument(
        "--runtime-config", type=Path, required=True, help=argparse.SUPPRESS
    )
    initial, _ = bootstrap.parse_known_args()
    runtime = json.loads(initial.runtime_config.read_text(encoding="utf-8"))
    bounded = runtime["bounded"]
    parser = argparse.ArgumentParser(
        prog="workstation-nix", description=__doc__, parents=[bootstrap]
    )
    parser.add_argument(
        "--memory-gib",
        type=int,
        choices=range(bounded["minimumMiB"] // 1024, bounded["maximumMiB"] // 1024 + 1),
        default=None,
    )
    parser.add_argument("--memory-min-gib", type=int)
    parser.add_argument("--memory-max-gib", type=int)
    parser.add_argument(
        "--state",
        type=Path,
        required=True,
        help="Retained private store and build receipts",
    )
    parser.add_argument(
        "--file", type=Path, help="Nix expression containing the package or check"
    )
    parser.add_argument("--impure", action="store_true")
    parser.add_argument("installables", nargs="*")
    args = parser.parse_args()
    if not args.file and not args.installables:
        parser.error("provide an installable or --file")
    elastic = args.memory_min_gib is not None or args.memory_max_gib is not None
    options = []
    if elastic:
        if (
            args.memory_gib is not None
            or args.memory_min_gib is None
            or args.memory_max_gib is None
            or not bounded["minimumMiB"]
            <= args.memory_min_gib * 1024
            <= args.memory_max_gib * 1024
            <= bounded["maximumMiB"]
        ):
            parser.error(
                "Supply a min/max GiB pair within the bounded profile without --memory-gib"
            )
        args.memory_gib = args.memory_min_gib
        options = [
            "--memory-min-mib",
            str(args.memory_min_gib * 1024),
            "--memory-max-mib",
            str(args.memory_max_gib * 1024),
        ]
    else:
        args.memory_gib = args.memory_gib or bounded["memoryMiB"] // 1024
        options = ["--bounded-memory", str(args.memory_gib)]
    try:
        if not allocation(args.memory_gib, args.memory_max_gib if elastic else None):
            os.execv(  # ruff: ignore[start-process-with-no-shell] - Fixed packaged runner, preserving argv.
                runtime["runner"],
                [
                    runtime["runner"],
                    *options,
                    sys.executable,
                    str(Path(__file__).resolve()),
                    *sys.argv[1:],
                ],
            )
        return build(args, runtime)
    except (ValueError, OSError) as error:
        sys.stderr.write(f"workstation-nix: {error}\n")
        return 1


if __name__ == "__main__":
    sys.exit(main())
