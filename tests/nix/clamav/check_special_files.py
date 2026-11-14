"""Exercise the scheduled scanner with an isolated real ClamAV daemon."""

# The Nix check supplies pinned executables and only disposable test paths.
# ruff: file-ignore[suspicious-subprocess-import, subprocess-without-shell-equals-true]

from __future__ import annotations

import array
import errno
import importlib.util
import os
import re
import select
import signal
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import TYPE_CHECKING

import pytest
from notification_process import run as run_command
from notification_process import wait_child

if TYPE_CHECKING:
    from collections.abc import Callable, Iterator
    from types import ModuleType

type Scanner = Callable[..., subprocess.CompletedProcess[str]]
SIGNATURE = b"LOCAL_CLAMAV_REGRESSION_SIGNATURE"
SCANNER_ERROR = 2


def wait_for_daemon(daemon: subprocess.Popen, path: Path) -> None:
    """Block on protocol data or exit after inheriting an already listening socket."""
    deadline = time.monotonic() + 10
    descriptor = os.pidfd_open(daemon.pid)
    try:
        with socket.socket(socket.AF_UNIX) as probe:
            probe.settimeout(max(0, deadline - time.monotonic()))
            probe.connect(str(path))
            probe.sendall(b"zPING\0")
            response = bytearray()
            while b"\0" not in response:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    pytest.fail("Fixture daemon did not become ready")
                ready = select.select([probe, descriptor], [], [], remaining)[0]
                if descriptor in ready:
                    pytest.fail("Fixture daemon exited before becoming ready")
                if probe not in ready:
                    pytest.fail("Fixture daemon did not become ready")
                chunk = probe.recv(32)
                if not chunk:
                    pytest.fail("Fixture daemon closed its readiness connection")
                response.extend(chunk)
            assert response == b"PONG\0"
    finally:
        os.close(descriptor)


@pytest.fixture
def daemon_socket(tmp_path: Path) -> Iterator[Path]:
    """Start an isolated daemon with one local signature.

    Yields:
        The ready isolated daemon's local socket.

    """
    binaries = Path(os.environ["CLAMAV_BIN"])
    database = tmp_path / "database"
    database.mkdir()
    (database / "fixture.ndb").write_text(f"LocalFixture:0:*:{SIGNATURE.hex()}\n")
    config = tmp_path / "clamd.conf"
    config.write_text(
        f"Foreground yes\nDatabaseDirectory {database}\n"
        f"LocalSocket {tmp_path}/clamd.sock\n"
        "FollowDirectorySymlinks no\nFollowFileSymlinks no\n",
    )
    with (
        (tmp_path / "daemon.log").open("w+") as log,
        socket.socket(socket.AF_UNIX) as listener,
    ):
        listener.bind(str(tmp_path / "clamd.sock"))
        # Match the client's four concurrent workers without manufacturing
        # accept saturation; a dedicated regression covers a full backlog.
        listener.listen(8)
        launcher = os.environ.get(
            "CLAMAV_FIXTURE_LAUNCHER",
            str(Path(__file__).with_name("activate_daemon.py")),
        )
        daemon = subprocess.Popen(
            [
                sys.executable,
                launcher,
                str(listener.fileno()),
                str(binaries / "clamd"),
                f"--config-file={config}",
            ],
            pass_fds=(listener.fileno(),),
            stdout=log,
            stderr=log,
        )
        listener.close()
        try:
            wait_for_daemon(daemon, tmp_path / "clamd.sock")

            yield tmp_path / "clamd.sock"
        finally:
            daemon.terminate()
            try:
                wait_child(daemon, timeout=5)
            except subprocess.TimeoutExpired:
                daemon.kill()
                wait_child(daemon, timeout=5)


@pytest.fixture(params=(1, 4))
def scanner(daemon_socket: Path, request: pytest.FixtureRequest) -> Scanner:
    """Invoke the installed scan source against the disposable daemon.

    Returns:
        A command that scans the supplied paths.

    """

    def scan(*paths: Path) -> subprocess.CompletedProcess[str]:
        return run_command(
            [
                sys.executable,
                os.environ["CLAMAV_SCAN_SCRIPT"],
                "--workers",
                str(request.param),
                str(daemon_socket),
                *map(str, paths),
            ],
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )

    return scan


@pytest.fixture
def scanner_module() -> ModuleType:
    """Load the same production source for deterministic eviction injection.

    Returns:
        The native scanner module.

    """
    specification = importlib.util.spec_from_file_location(
        "clamav_scan",
        os.environ["CLAMAV_SCAN_SCRIPT"],
    )
    assert specification is not None
    assert specification.loader is not None
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


def test_eviction_during_special_file_recheck(
    scanner_module: ModuleType,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A file replaced by a socket and then removed remains benign eviction."""
    target = tmp_path / "changing-file"
    target.write_bytes(b"fixture")
    original_open = os.open

    def replace_and_remove(
        name: str,
        flags: int,
        mode: int = 0o777,
        *,
        dir_fd: int | None = None,
    ) -> int:
        if name != str(target):
            return original_open(name, flags, mode, dir_fd=dir_fd)
        target.unlink()
        with socket.socket(socket.AF_UNIX) as replacement:
            replacement.bind(str(target))
            with pytest.raises(OSError, match=re.escape(str(target))) as failure:
                original_open(name, flags, mode, dir_fd=dir_fd)
            assert failure.value.errno in {errno.ENXIO, errno.ENODEV}
            target.unlink()
            raise failure.value

    monkeypatch.setattr(scanner_module.os, "open", replace_and_remove)
    assert scanner_module.open_regular(str(target)) is None


@pytest.mark.parametrize("when", ["before-open", "after-open"])
def test_cache_eviction(
    scanner_module: ModuleType,
    daemon_socket: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
    when: str,
) -> None:
    """Eviction before opening is benign; an already retained file is still scanned."""
    root = daemon_socket.parent / "cache"
    root.mkdir()
    target = root / "evicted"
    target.write_bytes(SIGNATURE)
    original = scanner_module.open_regular

    def evict(name: str, directory: int | None = None) -> int | None:
        if when == "before-open":
            target.unlink()
        descriptor = original(name, directory)
        if when == "after-open":
            target.unlink()
        return descriptor

    monkeypatch.setattr(scanner_module, "open_regular", evict)
    status = scanner_module.scan_roots(str(daemon_socket), [str(root)])
    assert status == (0 if when == "before-open" else 1)
    assert ("LocalFixture.UNOFFICIAL FOUND" in capsys.readouterr().out) == (
        when == "after-open"
    )


@pytest.mark.parametrize(
    "reply", [b"", b"malformed\0", b"fd[1]: scan failed ERROR\0", None]
)
def test_daemon_reply_failure(
    scanner_module: ModuleType,
    tmp_path: Path,
    reply: bytes | None,
) -> None:
    """Protocol failures stay visible and interruption releases blocked workers."""
    endpoint = tmp_path / "socket"
    sample = tmp_path / "sample"
    sample.write_bytes(b"ordinary content")
    released = threading.Event()
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as listener:
        listener.bind(str(endpoint))
        listener.listen(1)
        listener.settimeout(5)

        def respond() -> None:
            connection, _ = listener.accept()
            with connection:
                connection.settimeout(5)
                assert connection.recv(8, socket.MSG_WAITALL) == b"zFILDES\0"
                _, ancillary, _, _ = connection.recvmsg(1, socket.CMSG_SPACE(4))
                for _, _, data in ancillary:
                    descriptors = array.array("i")
                    descriptors.frombytes(data)
                    for descriptor in descriptors:
                        os.close(descriptor)
                if reply is None:
                    os.kill(os.getpid(), signal.SIGINT)
                    assert connection.recv(1) == b""
                    released.set()
                elif reply:
                    connection.sendall(reply)

        server = threading.Thread(target=respond)
        server.start()
        try:
            if reply is None:
                with pytest.raises(KeyboardInterrupt):
                    scanner_module.scan_roots(str(endpoint), [str(sample)])
            else:
                assert (
                    scanner_module.scan_roots(str(endpoint), [str(sample)])
                    == SCANNER_ERROR
                )
        finally:
            server.join(5)
            assert not server.is_alive()
        if reply is None:
            assert released.is_set()


def test_full_daemon_backlog(tmp_path: Path) -> None:
    """Accept saturation fails visibly instead of trapping a worker in connect."""
    endpoint = tmp_path / "socket"
    sample = tmp_path / "sample"
    sample.write_bytes(b"ordinary data")
    with (
        socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as listener,
        socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as queued,
    ):
        listener.bind(str(endpoint))
        listener.listen(0)
        queued.connect(str(endpoint))
        result = run_command(
            [
                sys.executable,
                os.environ["CLAMAV_SCAN_SCRIPT"],
                str(endpoint),
                str(sample),
            ],
            capture_output=True,
            text=True,
            timeout=2,
            check=False,
        )
    assert result.returncode == SCANNER_ERROR
    assert "Resource temporarily unavailable" in result.stdout


def test_clean_special_files_and_symlinks(scanner: Scanner, tmp_path: Path) -> None:
    """Sockets, FIFOs and symlinks do not turn a clean tree into a failure."""
    root = tmp_path / "scan"
    root.mkdir()
    (root / "ordinary").write_bytes(b"clean\0binary content")
    os.mkfifo(root / "pipe")
    outside = tmp_path / "outside"
    outside.mkdir()
    (outside / "detected").write_bytes(SIGNATURE)
    (root / "file-link").symlink_to(outside / "detected")
    (root / "directory-link").symlink_to(outside, target_is_directory=True)
    with socket.socket(socket.AF_UNIX) as listener:
        listener.bind(str(root / "socket"))
        result = scanner(root)
    assert result.returncode == 0, result.stdout + result.stderr


def test_all_batches_and_unusual_filenames(scanner: Scanner, tmp_path: Path) -> None:
    """Every regular file is scanned even after a preceding batch detects one."""
    root = tmp_path / "scan with ' quotes $dollar %percent"
    root.mkdir()
    names = [f"binary-{number}" for number in range(260)]
    names.extend(["-leading-dash", "line\nbreak", "space and ' quote"])
    for name in names:
        (root / name).write_bytes(b"\x00\xff" + SIGNATURE + b"\x00")
    result = scanner(root)
    assert result.returncode != 0
    assert result.stdout.count("LocalFixture.UNOFFICIAL FOUND") == len(names)


def test_missing_root_is_failure(scanner: Scanner, tmp_path: Path) -> None:
    """A missing input must not become a successful empty scan."""
    result = scanner(tmp_path / "missing")
    assert result.returncode != 0


@pytest.mark.parametrize("kind", ["directory", "file"])
def test_unreadable_input_is_failure(
    scanner: Scanner, tmp_path: Path, kind: str
) -> None:
    """Enumeration and descriptor-open errors both remain visible."""
    assert os.geteuid() != 0, "Run this check as the unprivileged build user"
    root = tmp_path / "scan"
    root.mkdir()
    file = root / "unreadable"
    file.write_bytes(b"ordinary data")
    protected = root if kind == "directory" else file
    protected.chmod(0)
    try:
        result = scanner(root)
        assert result.returncode != 0
    finally:
        protected.chmod(0o700)


def test_no_inputs_is_failure(scanner: Scanner) -> None:
    """An empty directory list must not scan the process working directory."""
    assert scanner().returncode != 0
