"""Wait for compositor changes through Hyprland's notification socket."""

from __future__ import annotations

import os
import socket
import subprocess  # ruff: ignore[suspicious-subprocess-import] -- Standard command failure and timeout exceptions.
from pathlib import Path
from time import monotonic
from typing import TYPE_CHECKING, Self

from notification_process import run as run_command

if TYPE_CHECKING:
    from collections.abc import Callable
    from types import TracebackType


class CompositorEvents:
    """Subscribe before taking a state snapshot, with one overall deadline."""

    def __init__(self, path: Path | None = None) -> None:
        """Select a running compositor or an isolated fixture socket.

        Raises:
            ValueError: Multiple instances require an explicit selection.

        """
        if path is None:
            directory = Path(os.environ["XDG_RUNTIME_DIR"]) / "hypr"
            signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
            if signature:
                path = directory / signature / ".socket2.sock"
            else:
                # VM commands run outside the compositor's child environment.
                # Select only an unambiguous instance, just as hyprctl does.
                paths = list(directory.glob("*/.socket2.sock"))
                if len(paths) != 1:
                    message = "Select a compositor with HYPRLAND_INSTANCE_SIGNATURE"
                    raise ValueError(message)
                path = paths[0]
        self.path = path
        self.socket = socket.socket(socket.AF_UNIX)
        self.buffer = b""
        self.deadline: float | None = None

    def __enter__(self) -> Self:
        """Connect before the caller dispatches work or reads current state.

        Returns:
            This subscribed observer.

        """
        try:
            self.socket.settimeout(5)
            self.socket.connect(str(self.path))
        except BaseException:
            self.socket.close()
            raise
        return self

    def __exit__(
        self,
        _kind: type[BaseException] | None,
        _error: BaseException | None,
        _traceback: TracebackType | None,
    ) -> None:
        """Close the subscription on success, timeout or failure."""
        self.socket.close()

    def wait(self, predicate: Callable[[], bool], timeout: float = 1) -> None:
        """Read state initially and after notifications, never on a timer.

        A false state at the deadline raises TimeoutError; a closed notification
        stream raises ConnectionError. Snapshot commands should use command()
        to share this deadline.

        """
        self.deadline = monotonic() + timeout
        try:
            self._wait(predicate)
        finally:
            self.deadline = None

    def observe(self, event: Callable[[str], None], timeout: float) -> None:
        """Deliver complete events while blocking through an observation interval.

        Unlike state snapshots, individual events retain brief open/close changes.
        A quiet stream completes at the deadline; disconnection still fails.

        Raises:
            ConnectionError: The compositor closes its notification stream.

        """
        self.deadline = monotonic() + timeout
        try:
            while True:
                remaining = self.deadline - monotonic()
                if remaining <= 0:
                    return
                if b"\n" in self.buffer:
                    line, self.buffer = self.buffer.split(b"\n", 1)
                    event(line.decode("utf-8"))
                    continue
                self.socket.settimeout(remaining)
                try:
                    chunk = self.socket.recv(65536)
                except TimeoutError:
                    return
                if not chunk:
                    message = "Hyprland notification stream closed"
                    raise ConnectionError(message)
                self.buffer += chunk
        finally:
            self.deadline = None

    def command(self, *args: str) -> str:
        """Read state with the remaining observer budget and reap owned children.

        Returns:
            UTF-8 command output.

        """
        timeout = 5 if self.deadline is None else self.deadline - monotonic()
        return command_output(*args, timeout=timeout)

    def _wait(self, predicate: Callable[[], bool]) -> None:
        assert self.deadline is not None
        while True:
            ready = predicate()
            remaining = self.deadline - monotonic()
            if remaining <= 0:
                raise TimeoutError
            if ready:
                return
            while b"\n" not in self.buffer:
                self.socket.settimeout(remaining)
                chunk = self.socket.recv(65536)
                if not chunk:
                    message = "Hyprland notification stream closed"
                    raise ConnectionError(message)
                self.buffer += chunk
                remaining = self.deadline - monotonic()
                if remaining <= 0:
                    raise TimeoutError
            # One snapshot covers all complete notifications already buffered.
            self.buffer = self.buffer.rsplit(b"\n", 1)[1]


def command_output(*args: str, timeout: float = 5) -> str:
    """Capture a bounded local command with the notification process ownership contract.

    Returns:
        UTF-8 command output.

    Raises:
        subprocess.TimeoutExpired: The command exhausts its execution budget.

    """
    if timeout <= 0:
        raise subprocess.TimeoutExpired(args, timeout)
    return run_command(
        args, check=True, capture_output=True, text=True, timeout=timeout
    ).stdout
