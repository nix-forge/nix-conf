"""Fault-inject stalled modifier replies without freezing the real compositor.

Run on an idle desktop with /dev/uinput access. Pass the Hyprshell binary to
exercise. Temporarily replaces the service with a daemon behind a private IPC
proxy, then restores the service and focus. Other compositor requests pass
through. Window titles and general IPC payloads are never printed.

    python3 tests/hyprland/check_alt_tab_ipc_timeout.py /path/to/hyprshell
"""

from __future__ import annotations

import json
import os
import select
import socket
import subprocess  # ruff: ignore[suspicious-subprocess-import] -- Local service and test daemon with explicit argv.
import sys
import tempfile
import threading
import time
from contextlib import suppress
from operator import itemgetter
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Callable

from check_alt_tab_timing import (
    ALT,
    ESC,
    HYPRCTL,
    _hypr,  # ruff: ignore[import-private-name] -- Reuse the live keyboard regression helpers.
    _key,  # ruff: ignore[import-private-name] -- Reuse the live keyboard regression helpers.
    _keyboard,  # ruff: ignore[import-private-name] -- Reuse the live keyboard regression helpers.
    _require,  # ruff: ignore[import-private-name] -- Reuse the live keyboard regression helpers.
    _run,  # ruff: ignore[import-private-name] -- Reuse the live keyboard regression helpers.
    _visible,  # ruff: ignore[import-private-name] -- Reuse the live keyboard regression helpers.
)

CLI_ARGUMENTS = 2
MIN_FINISHED_QUERIES = 3
MIN_WINDOWS = 2
MAX_QUERY_DURATION = 0.4


class _Proxy:
    def __init__(self, real_socket: Path) -> None:
        self.real_socket = real_socket
        self.stall = threading.Event()
        self.unsupported = threading.Event()
        self.seen = threading.Event()
        self.stopped = threading.Event()
        self.lock = threading.Lock()
        self.pending: list[socket.socket] = []
        self.durations: list[float] = []
        self.overlaps = 0
        self.received = 0

    def serve(self, listener: socket.socket) -> None:
        listener.settimeout(0.1)
        while not self.stopped.is_set():
            try:
                client, _ = listener.accept()
            except TimeoutError:  # ruff: ignore[try-except-continue] -- Periodically check test shutdown.
                continue
            except OSError:
                break
            threading.Thread(
                target=self._connection, args=(client,), daemon=True
            ).start()

    def _connection(self, client: socket.socket) -> None:
        with client:
            client.settimeout(3)
            try:
                self._reply(client)
            except OSError:
                # Cancellation closes the socket before a reply is delivered.
                return

    def _reply(self, client: socket.socket) -> None:
        data = client.recv(65536)
        if b"is_key_down" in data and self.unsupported.is_set():
            client.sendall(b"unknown request")
        elif b"is_key_down" in data and self.stall.is_set():
            self._stall_query(client)
        else:
            self._forward(client, data)

    def _forward(self, client: socket.socket, data: bytes) -> None:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as upstream:
            upstream.settimeout(3)
            upstream.connect(str(self.real_socket))
            upstream.sendall(data)
            while data := upstream.recv(65536):
                client.sendall(data)

    def _stall_query(self, client: socket.socket) -> None:
        started = time.monotonic()
        with self.lock:
            for previous in self.pending:
                with suppress(OSError):
                    ready = select.select([previous], [], [], 0)[0]
                    if not ready or previous.recv(1, socket.MSG_PEEK):
                        self.overlaps += 1
            self.pending.append(client)
            self.received += 1
        self.seen.set()
        try:
            # The client must close this connection on timeout or cancellation.
            with suppress(OSError):
                while client.recv(256):
                    pass
        finally:
            with self.lock:
                self.pending.remove(client)
                self.durations.append(time.monotonic() - started)

    def stop(self) -> None:
        self.stopped.set()
        with self.lock:
            for client in self.pending:
                with suppress(OSError):
                    client.shutdown(socket.SHUT_RDWR)


def _ipc(binary: str, env: dict[str, str], switch: bool | None) -> None:
    message = (
        {"OpenSwitch": {"reverse": False}}
        if switch is None
        else {"CloseSwitch": {"switch": switch}}
    )
    subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] -- Explicit local IPC argv and isolated environment.
        [binary, "socat", json.dumps(message)], env=env, check=True, timeout=2
    )


def _wait_visible(expected: bool, timeout: float, label: str) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if _visible() == expected:
            return
        time.sleep(0.005)
    _require(_visible() == expected, label)


def _exercise(binary: str, env: dict[str, str], proxy: _Proxy, fd: int) -> None:
    recent = sorted(_hypr("clients"), key=itemgetter("focusHistoryID"))
    _require(len(recent) >= MIN_WINDOWS, "Need two ordinary windows")
    expected = recent[1]["address"]
    _key(fd, ALT, 1)
    time.sleep(0.05)
    _ipc(binary, env, None)
    _wait_visible(True, 1, "Picker never opened")
    proxy.stall.set()
    _require(proxy.seen.wait(1), "No modifier check received")
    _key(fd, ESC, 1)
    _key(fd, ESC, 0)
    _wait_visible(
        False, 0.1, "FAIL: stalled modifier query blocked Escape/UI for 100 ms"
    )
    time.sleep(0.05)
    with proxy.lock:
        _require(not proxy.pending, "Escape left an IPC request running")
        cancelled_count = proxy.received
    time.sleep(0.2)
    _require(proxy.received == cancelled_count, "Polling continued after Escape")
    sys.stdout.write(
        "PASS: Escape responds during stalled IPC and cancels the request/timer\n"
    )
    sys.stdout.flush()

    # Reopen while Alt remains down. Old replies must not close this session.
    proxy.stall.clear()
    _ipc(binary, env, None)
    _wait_visible(True, 1, "Picker did not reopen after cancellation")
    time.sleep(0.25)
    _require(_visible(), "Cancelled request affected the new selection")
    proxy.seen.clear()
    proxy.stall.set()
    _require(proxy.seen.wait(1), "No stalled query in the new session")
    time.sleep(0.6)
    _require(_visible(), "Timeout selected a window with Alt still held")
    with proxy.lock:
        _require(
            len(proxy.durations) >= MIN_FINISHED_QUERIES,
            "Timed-out requests did not finish/retry",
        )
        _require(
            max(proxy.durations) < MAX_QUERY_DURATION,
            "Modifier query exceeded its deadline",
        )
        _require(proxy.overlaps == 0, "Multiple modifier requests overlapped")
    sys.stdout.write(
        "PASS: stalled requests time out and retry with only one in flight\n"
    )
    sys.stdout.flush()

    proxy.stall.clear()
    _key(fd, ALT, 0)
    _wait_visible(False, 1, "Picker did not recover when compositor replies resumed")
    time.sleep(0.1)
    _require(
        _hypr("activewindow").get("address") == expected,
        "Recovery focused the wrong window",
    )
    sys.stdout.write("PASS: switching recovers when compositor replies resume\n")


def _with_daemon(
    binary: str,
    proxy: _Proxy,
    directory: Path,
    log_fd: int,
    exercise: Callable[[str, dict[str, str], _Proxy, int], None] = _exercise,
) -> None:
    env = dict(os.environ, HYPRLAND_INSTANCE_SIGNATURE=directory.name)
    daemon = subprocess.Popen(  # ruff: ignore[subprocess-without-shell-equals-true] -- Explicit test binary, no shell.
        [binary, "run"], env=env, stdout=log_fd, stderr=log_fd
    )
    binding_socket = proxy.real_socket.parent / "hyprshell.sock"
    test_socket = directory / "hyprshell.sock"
    try:
        time.sleep(2)
        _require(daemon.poll() is None, "Test daemon failed to start")
        _require(test_socket.is_socket(), "Test daemon socket was not created")
        # Compositor-spawned commands inherit the real instance signature.
        # Route those commands to this daemon while the normal service is stopped.
        binding_socket.unlink(missing_ok=True)
        binding_socket.symlink_to(test_socket)
        with _keyboard() as fd:
            exercise(binary, env, proxy, fd)
    finally:
        if binding_socket.is_symlink() and binding_socket.readlink() == test_socket:
            binding_socket.unlink()
        daemon.terminate()
        try:
            daemon.wait(timeout=2)
        except subprocess.TimeoutExpired:
            daemon.kill()
            daemon.wait()
        proxy.stop()


def _check(
    binary: str,
    exercise: Callable[[str, dict[str, str], _Proxy, int], None] = _exercise,
    expected_warnings: int | None = 1,
) -> None:
    real = (
        Path(os.environ["XDG_RUNTIME_DIR"])
        / "hypr"
        / os.environ["HYPRLAND_INSTANCE_SIGNATURE"]
    )
    original = _hypr("activewindow").get("address")
    _require(not _visible(), "Close the picker before testing")
    _run("systemctl", "--user", "stop", "hyprshell.service")
    try:
        with tempfile.TemporaryDirectory(prefix="alt-tab-ipc-", dir=real.parent) as tmp:
            directory = Path(tmp)
            (directory / ".socket2.sock").symlink_to(real / ".socket2.sock")
            proxy = _Proxy(real / ".socket.sock")
            with (
                socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as listener,
                tempfile.TemporaryFile(mode="w+", encoding="utf-8") as log,
            ):
                listener.bind(str(directory / ".socket.sock"))
                listener.listen()
                thread = threading.Thread(
                    target=proxy.serve, args=(listener,), daemon=True
                )
                thread.start()
                try:
                    _with_daemon(binary, proxy, directory, log.fileno(), exercise)
                finally:
                    proxy.stop()
                    thread.join(timeout=1)
                log.seek(0)
                warnings = log.read().count("Could not read switch modifier state")
                if expected_warnings is not None:
                    _require(
                        warnings == expected_warnings,
                        f"Expected {expected_warnings} warnings, got {warnings}",
                    )
                    sys.stdout.write(
                        "PASS: expected warning count during fault injection\n"
                    )
    finally:
        _run("systemctl", "--user", "start", "hyprshell.service")
        time.sleep(2)
        if isinstance(original, str) and original in {
            client["address"] for client in _hypr("clients")
        }:
            _run(
                HYPRCTL,
                "dispatch",
                "hl.dsp.focus({window=" + json.dumps("address:" + original) + "})",
            )


if __name__ == "__main__":
    _require(len(sys.argv) == CLI_ARGUMENTS, "Pass the Hyprshell binary to test")
    _check(sys.argv[1])
