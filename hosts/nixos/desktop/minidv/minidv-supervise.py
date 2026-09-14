"""Supervise a DV capture using FireWire events, child exit, and stop deadlines."""

from __future__ import annotations

import argparse
import contextlib
import os
import selectors
import signal
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Runs the pinned dvgrab command without a shell.
import sys
import time
from pathlib import Path
from typing import TYPE_CHECKING, Protocol

import pyudev

if TYPE_CHECKING:
    from collections.abc import Callable, Sequence
    from types import FrameType


class DeviceMonitor(Protocol):
    """Selectable device event source, replaceable by a pipe in runtime tests."""

    def start(self) -> None:
        """Subscribe before taking a snapshot."""

    def fileno(self) -> int:
        """Return the event descriptor."""

    def poll(self, timeout: int = 0) -> object | None:
        """Consume a pending event."""


def camera_present(root: Path, guid: str) -> bool:
    """Find the selected GUID, regardless of node numbering.

    Returns:
        Whether the selected remote camera is currently present.

    """
    for device in root.glob("fw*"):
        try:
            if (device / "is_local").read_text().strip() == "0" and (
                device / "guid"
            ).read_text().strip().lower() == f"0x{guid.lower()}":
                return True
        except FileNotFoundError:  # ruff: ignore[try-except-in-loop, try-except-pass] - Removal can race each read.
            pass
    return False


def supervise(  # ruff: ignore[complex-structure, too-many-branches, too-many-statements] - Keep descriptor and child lifetimes together.
    command: Sequence[str],
    monitor: DeviceMonitor,
    present: Callable[[], bool],
    lost_marker: Path,
    *,
    grace_seconds: float = 5,
) -> int:
    """Wait for child exit, camera removal, or cancellation.

    Returns:
        Capture status, 130 for interruption, or 1 after a disconnect.

    """
    interrupted = False

    def request_stop(_number: int, _frame: FrameType | None) -> None:
        nonlocal interrupted
        interrupted = True

    def camera_lost() -> None:
        lost_marker.touch()
        sys.stderr.write(
            "minidv-capture: selected camera disappeared from the FireWire bus; "
            "stopping the incomplete capture.\n"
        )

    with contextlib.ExitStack() as cleanup, selectors.DefaultSelector() as selector:  # ruff: ignore[too-many-nested-blocks] - Explicit cleanup spans the event loop.
        read_fd, write_fd = os.pipe2(os.O_NONBLOCK | os.O_CLOEXEC)
        cleanup.callback(os.close, read_fd)
        cleanup.callback(os.close, write_fd)
        for number in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            previous = signal.signal(number, request_stop)
            cleanup.callback(signal.signal, number, previous)
        previous_wakeup = signal.set_wakeup_fd(write_fd, warn_on_full_buffer=False)
        cleanup.callback(signal.set_wakeup_fd, previous_wakeup)
        selector.register(read_fd, selectors.EVENT_READ, "signal")
        monitor.start()
        selector.register(monitor, selectors.EVENT_READ, "device")
        if interrupted:
            return 130
        if not present():
            camera_lost()
            return 1

        # A separate session leaves all stop handling with this supervisor.
        # Custom Python signal handlers become default dispositions on exec.
        child = subprocess.Popen(command, start_new_session=True)  # ruff: ignore[subprocess-without-shell-equals-true]
        try:
            pid_fd = os.pidfd_open(child.pid)
            cleanup.callback(os.close, pid_fd)
            selector.register(pid_fd, selectors.EVENT_READ, "child")
            deadline = None
            stop_signal = None
            disconnected = False
            while True:
                if interrupted and stop_signal is None:
                    sys.stderr.write(
                        "Stopping dvgrab and retaining the partial capture...\n"
                    )
                    child.send_signal(signal.SIGINT)
                    stop_signal = signal.SIGINT
                    deadline = time.monotonic() + grace_seconds
                timeout = (
                    None if deadline is None else max(0, deadline - time.monotonic())
                )
                events = selector.select(timeout)
                if any(key.data == "child" for key, _ in events):
                    status = child.wait()
                    if interrupted:
                        return 130
                    return (
                        1 if disconnected else (status if status >= 0 else 128 - status)
                    )
                for key, _ in events:
                    if key.data == "signal":
                        os.read(read_fd, 4096)
                    elif key.data == "device":
                        # Coalesce pending notifications before checking current state.
                        while monitor.poll(timeout=0) is not None:
                            pass
                        if stop_signal is None and not present():
                            camera_lost()
                            disconnected = True
                            child.terminate()
                            stop_signal = signal.SIGTERM
                            deadline = time.monotonic() + grace_seconds
                if deadline is not None and time.monotonic() >= deadline:
                    if stop_signal == signal.SIGINT:
                        sys.stderr.write(
                            "dvgrab did not exit after SIGINT; sending SIGTERM...\n"
                        )
                        child.terminate()
                        stop_signal = signal.SIGTERM
                        deadline = time.monotonic() + grace_seconds
                    else:
                        sys.stderr.write(
                            "dvgrab is unresponsive; force-stopping it without removing captured data.\n"
                        )
                        child.kill()
                        deadline = None
        finally:
            # A monitor/read failure must never leave an unsupervised capture.
            if child.poll() is None:
                child.kill()
            child.wait()


def main() -> int:
    """Supervise a capture using a udev subscription.

    Returns:
        The capture status, or 1 if supervision fails.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("guid")
    parser.add_argument("lost_marker", type=Path)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if not args.command:
        parser.error("a capture command is required")
    monitor = pyudev.Monitor.from_netlink(pyudev.Context())
    monitor.filter_by(subsystem="firewire")
    try:
        return supervise(
            args.command,
            monitor,
            lambda: camera_present(Path("/sys/bus/firewire/devices"), args.guid),
            args.lost_marker,
        )
    except OSError as error:
        sys.stderr.write(f"minidv-capture: capture supervision failed: {error}\n")
        return 1


if __name__ == "__main__":
    sys.exit(main())
