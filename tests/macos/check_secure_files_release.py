"""Exercise interruption and exec behavior of the installed release helper."""

from __future__ import annotations

import json
import os
import select
import signal
import socket
import subprocess
import sys
import tempfile
from pathlib import Path

TIMEOUT = 10
CHILD_EXIT = 37
ORIGINAL = b"original fixture bytes\x00\xff\n"


def reap(child: subprocess.Popen[bytes]) -> None:
    """Reap an owned fixture even when a check fails."""
    if child.poll() is None:
        child.kill()
    child.communicate(timeout=TIMEOUT)


def check_interrupted_write(
    binary: str, root: Path, termination: signal.Signals
) -> None:
    """Preserve the original file when input is interrupted before EOF."""
    directory = root / f"write-{termination.name}"
    directory.mkdir(mode=0o700)
    destination = directory / "state"
    destination.write_bytes(ORIGINAL)
    destination.chmod(0o600)
    before = destination.stat()
    reader, writer = socket.socketpair()
    with reader, writer:
        # A small send buffer and a larger payload force the helper to read
        # input before sendall completes. Keeping this socket open withholds EOF.
        writer.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 4096)
        writer.settimeout(TIMEOUT)
        child = subprocess.Popen(
            [binary, "atomic-write", str(destination), "600"],
            stdin=reader.fileno(),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        try:
            reader.close()
            writer.sendall(b"replacement fixture\n" * 131_072)
            assert child.poll() is None, "writer must await EOF"
            child.send_signal(termination)
            stdout, stderr = child.communicate(timeout=TIMEOUT)
            assert child.returncode == -termination, (child.returncode, stderr)
            assert not stdout, stdout
            assert not stderr, stderr
            after = destination.stat()
            assert destination.read_bytes() == ORIGINAL
            assert (after.st_dev, after.st_ino, after.st_mode) == (
                before.st_dev,
                before.st_ino,
                before.st_mode,
            )
            assert sorted(path.name for path in directory.iterdir()) == ["state"]
        finally:
            reap(child)


def fixture() -> None:
    """Announce exec readiness, then accept an exit request or an external signal."""
    mapped = Path(sys.argv[2]).read_bytes().hex() if len(sys.argv) == 3 else None
    record = json.dumps({"pid": os.getpid(), "cwd": str(Path.cwd()), "mapped": mapped})
    os.write(sys.stdout.fileno(), record.encode() + b"\n")
    assert sys.stdin.buffer.readline() == b"exit\n"
    sys.exit(CHILD_EXIT)


def check_exec(
    binary: str, root: Path, command: str, termination: signal.Signals | None
) -> None:
    """Preserve the service PID, exit status and signal semantics across exec."""
    outcome = termination.name if termination is not None else "exit"
    directory = root / f"{command}-{outcome}"
    directory.mkdir(mode=0o700)
    arguments = [binary, command, str(directory), sys.executable]
    fixture_arguments = [str(Path(__file__).resolve()), "--fixture"]
    if command == "exec-files":
        source = directory / "input"
        source.write_bytes(ORIGINAL)
        source.chmod(0o600)
        arguments.extend(["--read", "input", "600", "--"])
        fixture_arguments.append("@input@")
    arguments.extend(fixture_arguments)
    child = subprocess.Popen(
        arguments, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    try:
        assert child.stdout is not None
        ready, _, _ = select.select([child.stdout], [], [], TIMEOUT)
        assert ready, "exec fixture did not announce readiness"
        # One small flushed write supplies the complete readiness record.
        record = json.loads(os.read(child.stdout.fileno(), 4096))
        assert record["pid"] == child.pid, "helper must exec in place"
        assert record["cwd"] == str(directory)
        assert record["mapped"] == (ORIGINAL.hex() if command == "exec-files" else None)
        if termination is None:
            stdout, stderr = child.communicate(b"exit\n", timeout=TIMEOUT)
            expected_status = CHILD_EXIT
        else:
            child.send_signal(termination)
            stdout, stderr = child.communicate(timeout=TIMEOUT)
            expected_status = -termination
        assert child.returncode == expected_status, (command, child.returncode, stderr)
        assert not stdout, stdout
        assert not stderr, stderr
        if command == "exec-files":
            assert (directory / "input").read_bytes() == ORIGINAL
            assert sorted(path.name for path in directory.iterdir()) == ["input"]
        else:
            assert list(directory.iterdir()) == []
    finally:
        reap(child)


def main() -> None:
    """Run native release checks in canonical, disposable private directories."""
    if sys.argv[1:2] == ["--fixture"]:
        fixture()
        return
    assert len(sys.argv) == 2, "usage: check_secure_files_release.py RELEASE_BINARY"
    binary = str(Path(sys.argv[1]).resolve(strict=True))
    with tempfile.TemporaryDirectory(prefix="secure-files-release-") as temporary:
        root = Path(temporary).resolve(strict=True)
        root.chmod(0o700)
        for termination in (signal.SIGTERM, signal.SIGKILL):
            check_interrupted_write(binary, root, termination)
        for command in ("exec-private-directory", "exec-files"):
            for termination in (None, signal.SIGTERM, signal.SIGKILL):
                check_exec(binary, root, command, termination)
    print("secure-files release interruption and exec checks passed")


if __name__ == "__main__":
    main()
