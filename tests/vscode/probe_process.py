"""Own disposable Code fixtures through startup failure and parent disappearance."""

from __future__ import annotations

import argparse
import contextlib
import os
import plistlib
import shutil
import signal
import subprocess  # ruff: ignore[suspicious-subprocess-import] -- Constants for owned control commands.
import sys
from pathlib import Path
from threading import Timer
from typing import TYPE_CHECKING

from notification_process import defer_cancellation
from notification_process import run as run_command

if TYPE_CHECKING:
    from collections.abc import Generator, Mapping, Sequence
    from types import FrameType


def _cancel(signum: int, _frame: FrameType | None) -> None:
    raise SystemExit(128 + signum)


def _native_code(executable: str) -> str:
    resolved = Path(shutil.which(executable) or executable).resolve()
    bundles = [parent for parent in resolved.parents if parent.suffix == ".app"]
    bundles.extend(resolved.parent.parent.glob("Applications/*.app"))
    for bundle in bundles:
        info = bundle / "Contents/Info.plist"
        if info.is_file():
            with info.open("rb") as stream:
                metadata = plistlib.load(stream)
            binary = bundle / "Contents/MacOS" / metadata["CFBundleExecutable"]
            if binary.is_file():
                return str(binary)
    message = "Pass the Code executable from its application bundle"
    raise ValueError(message)


@contextlib.contextmanager
def _cancellation_handlers() -> Generator[None]:
    previous = {}
    try:
        with defer_cancellation():
            for signum in (signal.SIGTERM, signal.SIGHUP):
                previous[signum] = signal.signal(signum, _cancel)
        yield
    finally:
        with defer_cancellation():
            for signum, handler in previous.items():
                signal.signal(signum, handler)


def _stop_probe(pid: int, unit: str | None, env: Mapping[str, str]) -> None:
    try:
        if unit:
            run_command(
                ["systemctl", "--user", "stop", unit],
                timeout=15,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                env=env,
            )
            state = run_command(
                ["systemctl", "--user", "is-active", unit],
                timeout=5,
                capture_output=True,
                text=True,
                env=env,
            ).stdout.strip()
            if state not in {"inactive", "failed", "unknown"}:
                message = f"Probe scope did not stop: {unit}: {state}"
                raise RuntimeError(message)
    finally:
        # The unreaped leader retains the process-group identity through cleanup.
        with contextlib.suppress(ProcessLookupError):
            os.killpg(pid, signal.SIGKILL)
        os.waitpid(pid, 0)


def _finish_probe(
    pid: int | None, unit: str | None, env: Mapping[str, str], timer: Timer
) -> None:
    with defer_cancellation():
        timer.cancel()
        if timer.ident is not None:
            timer.join()
        if pid is None:
            return
        original_error = sys.exception()
        try:
            _stop_probe(pid, unit, env)
        except Exception as error:
            if original_error is None:
                raise
            original_error.add_note(f"Probe cleanup failed: {error}")


@contextlib.contextmanager
def owned_probe(
    root: Path, arguments: Sequence[str], *, env: Mapping[str, str] | None = None
) -> Generator[None]:
    """Keep the native leader unreaped until termination; Linux owns a scope too.

    Raises:
        ValueError: No Code executable was provided.
        NotImplementedError: The host lacks a supported ownership mechanism.

    """
    command = list(arguments)
    if not command:
        message = "Pass the Code executable and its arguments"
        raise ValueError(message)
    environment = dict(os.environ if env is None else env)
    unit = None
    if sys.platform == "linux":
        unit = f"{root.name}.scope"
        runtime = root / "runtime"
        runtime.mkdir(mode=0o700, exist_ok=True)
        display = environment.get("WAYLAND_DISPLAY", "")
        if display and not Path(display).is_absolute():
            display = str(Path(environment["XDG_RUNTIME_DIR"]) / display)
        command = [
            "systemd-run",
            "--user",
            "--scope",
            "--collect",
            "--expand-environment=no",
            f"--unit={unit}",
            "--property=RuntimeMaxSec=180s",
            "--property=TimeoutStopSec=5s",
            "--",
            "env",
            f"XDG_RUNTIME_DIR={runtime}",
            f"WAYLAND_DISPLAY={display}",
            "dbus-run-session",
            "--",
            command[0],
            "--wait",
            *command[1:],
        ]
    elif sys.platform == "darwin":
        command[0] = _native_code(command[0])
    else:
        message = "Disposable Code fixtures require Linux or macOS"
        raise NotImplementedError(message)
    executable = shutil.which(command[0], path=environment.get("PATH")) or command[0]
    pid = None
    timer = Timer(180, lambda: os.kill(os.getpid(), signal.SIGTERM))
    original_mask = signal.pthread_sigmask(signal.SIG_BLOCK, [])
    with _cancellation_handlers(), (root / "code.log").open("wb") as log:
        try:
            with defer_cancellation():
                pid = os.posix_spawn(
                    executable,
                    command,
                    environment,
                    setsid=True,
                    setsigmask=original_mask,
                    setsigdef=tuple(
                        getattr(signal, name)
                        for name in ("SIGPIPE", "SIGXFZ", "SIGXFSZ")
                        if hasattr(signal, name)
                    ),
                    file_actions=[
                        (os.POSIX_SPAWN_DUP2, log.fileno(), 1),
                        (os.POSIX_SPAWN_DUP2, log.fileno(), 2),
                    ],
                )
                timer.start()
            yield
        finally:
            _finish_probe(pid, unit, environment, timer)


def main() -> None:
    """EOF from the owning Node process closes the fixture even after a crash."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    with owned_probe(args.root, args.arguments):
        sys.stdin.buffer.read()


if __name__ == "__main__":
    main()
