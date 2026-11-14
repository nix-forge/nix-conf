"""Exercise native SOCKS authentication using disposable file credentials."""

# Disposable executable regression: subprocess inputs are fixed fixtures and
# assertions deliberately fail the package build on protocol regressions.
# ruff: file-ignore[suspicious-subprocess-import, subprocess-without-shell-equals-true, assert, print, raise-vanilla-args, raw-string-in-exception]

import os
import select
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from notification_process import communicate_and_reap
from notification_process import run as run_command

BINARY = str(Path(sys.argv[1]).resolve())
USER = b"fixture-reader"
PASSWORD = b"fixture-password"


def _free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def _connect(port: int, process: subprocess.Popen) -> socket.socket:
    """Bound safe connection retries for a server without a readiness protocol.

    The server supplies no ready descriptor. Refused TCP connections may be
    retried with positive backoff; child exit interrupts that backoff through a
    pidfd without reaping the child needed by pipe cleanup.

    Returns:
        A connected protocol socket.

    Raises:
        AssertionError: The server exits or fails to listen within the deadline.

    """
    deadline = time.monotonic() + 5
    delay = 0.01
    descriptor = os.pidfd_open(process.pid)
    try:
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise AssertionError("Proxy did not start")
            try:
                return socket.create_connection(("127.0.0.1", port), timeout=remaining)
            except ConnectionRefusedError:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise AssertionError("Proxy did not start") from None
                if select.select([descriptor], [], [], min(delay, remaining))[0]:
                    raise AssertionError(
                        "Proxy exited before accepting authentication"
                    ) from None
                delay = min(delay * 2, 0.5)
    finally:
        os.close(descriptor)


def _authentication(port: int, process: subprocess.Popen, password: bytes) -> bytes:
    with _connect(port, process) as sock:
        sock.sendall(b"\x05\x01\x02")
        assert sock.recv(2) == b"\x05\x02"
        sock.sendall(
            b"\x01" + bytes([len(USER)]) + USER + bytes([len(password)]) + password
        )
        return sock.recv(2)


with tempfile.TemporaryDirectory() as directory:
    user = Path(directory) / "username"
    password = Path(directory) / "password"
    user.write_bytes(USER + b"\n")
    password.write_bytes(PASSWORD + b"\r\n")
    env = {
        **os.environ,
        "MICROSOCKS_USERNAME_FILE": str(user),
        "MICROSOCKS_PASSWORD_FILE": str(password),
    }
    port = _free_port()
    args = [BINARY, "-i", "127.0.0.1", "-p", str(port), "-q"]
    process = subprocess.Popen(
        args,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
    )
    try:
        assert _authentication(port, process, PASSWORD) == b"\x01\x00"
        assert _authentication(port, process, b"wrong") == b"\x01\x02"
        with _connect(port, process) as sock:
            sock.sendall(b"\x05\x01\x00")
            assert sock.recv(2) == b"\x05\xff"
        commandline = Path(f"/proc/{process.pid}/cmdline").read_bytes()
        assert USER not in commandline
        assert PASSWORD not in commandline
        environment = Path(f"/proc/{process.pid}/environ").read_bytes()
        assert USER not in environment
        assert PASSWORD not in environment
    finally:
        process.terminate()
        output, errors = communicate_and_reap(process, timeout=5)
        assert USER not in output + errors
        assert PASSWORD not in output + errors
    password.write_bytes(b"x" * 255 + b"\r\n")
    port = _free_port()
    args = [BINARY, "-i", "127.0.0.1", "-p", str(port), "-q"]
    process = subprocess.Popen(
        args,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
    )
    try:
        assert _authentication(port, process, b"x" * 255) == b"\x01\x00"
    finally:
        process.terminate()
        communicate_and_reap(process, timeout=5)
    for invalid in (b"", b"x" * 256, b"x\ny", b"x\0y"):
        password.write_bytes(invalid)
        result = run_command(args, env=env, capture_output=True, timeout=5, check=False)
        assert result.returncode != 0
    password.write_bytes(PASSWORD)
    for bad_env, flags in (
        ({**env, "MICROSOCKS_PASSWORD_FILE": str(password) + ".missing"}, []),
        (
            {
                key: value
                for key, value in env.items()
                if key != "MICROSOCKS_PASSWORD_FILE"
            },
            [],
        ),
        (env, ["-u", "fixture-reader", "-P", "fixture-password"]),
    ):
        result = run_command(
            args + flags, env=bad_env, capture_output=True, timeout=5, check=False
        )
        assert result.returncode != 0
print("MicroSocks file credentials: authentication and fail-closed checks passed")
