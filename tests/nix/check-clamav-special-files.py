"""Exercise the scheduled scanner with an isolated real ClamAV daemon."""

# The Nix check supplies pinned executables and only disposable test paths.
# ruff: file-ignore[suspicious-subprocess-import, subprocess-without-shell-equals-true, start-process-with-partial-path]

from __future__ import annotations

import contextlib
import os
import shlex
import shutil
import socket
import subprocess
import time
from pathlib import Path
from typing import TYPE_CHECKING

import pytest

if TYPE_CHECKING:
    from collections.abc import Callable, Iterator

type Scanner = Callable[..., subprocess.CompletedProcess[str]]
SIGNATURE = b"LOCAL_CLAMAV_REGRESSION_SIGNATURE"


def wait_for_daemon(daemon: subprocess.Popen, path: Path) -> None:
    """Wait for a real protocol response while keeping startup bounded."""
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline and daemon.poll() is None:
        with contextlib.suppress(OSError), socket.socket(socket.AF_UNIX) as probe:
            probe.settimeout(0.2)
            probe.connect(str(path))
            probe.sendall(b"zPING\0")
            if probe.recv(32) == b"PONG\0":
                return
        time.sleep(0.05)
    pytest.fail("Fixture daemon did not become ready")


@pytest.fixture
def scanner(tmp_path: Path) -> Iterator[Scanner]:
    """Start an isolated daemon with one local signature.

    Yields:
        A command that scans input directories through that daemon.

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
    client = tmp_path / "client"
    client.write_text(
        f"#!{shutil.which('bash')}\nexec "
        + shlex.join([str(binaries / "clamdscan"), f"--config-file={config}"])
        + ' "$@"\n',
    )
    client.chmod(0o700)
    with (tmp_path / "daemon.log").open("w+") as log:
        daemon = subprocess.Popen(
            [str(binaries / "clamd"), f"--config-file={config}"],
            stdout=log,
            stderr=log,
        )
        try:
            wait_for_daemon(daemon, tmp_path / "clamd.sock")

            def scan(*paths: Path) -> subprocess.CompletedProcess[str]:
                return subprocess.run(
                    [
                        "bash",
                        os.environ["CLAMAV_SCAN_SCRIPT"],
                        str(client),
                        *map(str, paths),
                    ],
                    capture_output=True,
                    text=True,
                    timeout=30,
                    check=False,
                )

            yield scan
        finally:
            daemon.terminate()
            try:
                daemon.wait(timeout=5)
            except subprocess.TimeoutExpired:
                daemon.kill()
                daemon.wait(timeout=5)


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
