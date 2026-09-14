"""Exercise capture supervision with real pipes/processes and fake FireWire sysfs."""

from __future__ import annotations

import contextlib
import importlib.util
import os
import select
import shutil
import signal
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Disposable test processes.
import sys
from pathlib import Path
from typing import TYPE_CHECKING

import pytest

if TYPE_CHECKING:
    from collections.abc import Iterator

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "hosts/nixos/desktop/minidv/minidv-supervise.py"
INTERRUPTED_STATUS = 130
pytestmark = pytest.mark.skipif(sys.platform != "linux", reason="Requires Linux pidfds")

# Keep the hardware replacement at the selectable-monitor and sysfs boundaries.
# The actual supervisor still owns real child and signal handling in this process.
WORKER = """
import importlib.util
import os
import sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("supervisor", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
root = Path(sys.argv[2])
fd = int(sys.argv[3])
class Monitor:
    def start(self):
        (root / "subscribed").touch()
    def fileno(self):
        return fd
    def poll(self, timeout=0):
        try:
            data = os.read(fd, 1)
        except BlockingIOError:
            return None
        if data == b"E":
            raise OSError("fixture monitor failed")
        return data or None

def present():
    assert (root / "subscribed").exists()
    with (root / "snapshots").open("a") as handle:
        handle.write("snapshot\\n")
    return module.camera_present(root, "aabb")

sys.exit(module.supervise(
    [sys.executable, "-c", sys.argv[4]], Monitor(), present,
    root / "camera-disconnected", grace_seconds=0.1,
))
"""

CHILD = """
import os
import signal
import sys

def stop(number, frame):
    print("signal=" + str(number), flush=True)
    if sys.argv[1] == "exit":
        sys.exit(0)

signal.signal(signal.SIGINT, stop)
signal.signal(signal.SIGTERM, stop)
print("ready=" + str(os.getpid()), flush=True)
os.read(0, 1)
"""


def camera(root: Path, name: str = "fw1", guid: str = "0xaabb") -> Path:
    """Create a disposable remote device.

    Returns:
        The fixture node directory.

    """
    device = root / name
    device.mkdir()
    (device / "is_local").write_text("0\n")
    (device / "guid").write_text(f"{guid}\n")
    return device


@contextlib.contextmanager
def running(
    root: Path, *, ignore_stop: bool = False
) -> Iterator[tuple[subprocess.Popen[bytes], int]]:
    """Start the real supervisor in a child with a selectable fixture monitor.

    Yields:
        The supervisor process and device-event write descriptor.

    """
    event_read, event_write = os.pipe2(os.O_NONBLOCK | os.O_CLOEXEC)
    child_code = (
        "import sys; sys.argv = ['capture', "
        + repr("ignore" if ignore_stop else "exit")
        + "]\n"
        + CHILD
    )
    process = subprocess.Popen(  # ruff: ignore[subprocess-without-shell-equals-true] - Fixed interpreter and test source.
        [
            sys.executable,
            "-c",
            WORKER,
            str(SOURCE),
            str(root),
            str(event_read),
            child_code,
        ],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        pass_fds=(event_read,),
    )
    os.close(event_read)
    try:
        yield process, event_write
    finally:
        if process.poll() is None:
            process.terminate()
        process.communicate(timeout=3)
        os.close(event_write)


def ready(process: subprocess.Popen[bytes]) -> int:
    """Wait for the capture to install its handlers.

    Returns:
        The capture child PID.

    """
    assert process.stdout is not None
    assert select.select([process.stdout], [], [], 3)[0], "capture did not start"
    line = process.stdout.readline()
    assert line.startswith(b"ready="), line
    return int(line.partition(b"=")[2])


def finish(process: subprocess.Popen[bytes]) -> tuple[bytes, bytes]:
    """Wait for capture.

    Returns:
        Captured standard output and error.

    """
    process.wait(timeout=3)
    output = process.communicate(timeout=3)
    assert process.returncode is not None
    return output


def test_idle_capture_takes_no_periodic_snapshots(tmp_path: Path) -> None:
    """A paused camera and unrelated events do not end capture or trigger timers."""
    camera(tmp_path)
    with running(tmp_path) as (process, event):
        ready(process)
        assert process.stdout is not None
        assert not select.select([process.stdout], [], [], 1.2)[0]
        assert (tmp_path / "snapshots").read_text() == "snapshot\n"
        # The GUID survives node renumbering; another camera's removal is harmless.
        (tmp_path / "fw1").rename(tmp_path / "fw7")
        os.write(event, b"change")
        assert not select.select([process.stdout], [], [], 0.15)[0]
        assert process.poll() is None
        assert not (tmp_path / "camera-disconnected").exists()
        process.communicate(input=b"done", timeout=3)
        assert process.returncode == 0


def test_disconnect_stops_capture_and_preserves_data(tmp_path: Path) -> None:
    """Removing the selected GUID terminates capture and retains partial data."""
    device = camera(tmp_path)
    partial = tmp_path / "partial.dv"
    partial.write_bytes(b"captured frames")
    with running(tmp_path) as (process, event):
        ready(process)
        shutil.rmtree(device)
        camera(tmp_path, "fw2", "0xccdd")
        os.write(event, b"remove")
        output, error = finish(process)
        assert process.returncode == 1
        assert b"signal=15" in output
        assert b"disappeared" in error
        assert (tmp_path / "camera-disconnected").exists()
        assert partial.read_bytes() == b"captured frames"


def test_missing_camera_is_checked_after_subscribing(tmp_path: Path) -> None:
    """Removal before the initial snapshot prevents capture from starting."""
    with running(tmp_path) as (process, _event):
        output, _error = finish(process)
        assert output == b""
        assert process.returncode == 1
        assert (tmp_path / "subscribed").exists()
        assert (tmp_path / "camera-disconnected").exists()


@pytest.mark.parametrize("stop_signal", [signal.SIGINT, signal.SIGTERM, signal.SIGHUP])
def test_cancellation_signals_request_graceful_stop(
    tmp_path: Path, stop_signal: int
) -> None:
    """Each supported cancellation signal requests SIGINT and returns interruption."""
    camera(tmp_path)
    with running(tmp_path) as (process, _event):
        child_pid = ready(process)
        process.send_signal(stop_signal)
        output, _error = finish(process)
        assert output == b"signal=2\n"
        assert process.returncode == INTERRUPTED_STATUS
        assert not Path(f"/proc/{child_pid}").exists()
        assert not (tmp_path / "camera-disconnected").exists()


def test_unresponsive_child_is_killed_after_stop_deadlines(tmp_path: Path) -> None:
    """An ignored interrupt escalates to TERM then KILL without polling."""
    camera(tmp_path)
    with running(tmp_path, ignore_stop=True) as (process, _event):
        child_pid = ready(process)
        process.terminate()
        # Keep stdin open so only signal handling can stop this fake capture.
        assert process.stdout is not None
        process.wait(timeout=3)
        output, error = finish(process)
        assert output == b"signal=2\nsignal=15\n"
        assert b"force-stopping" in error
        assert process.returncode == INTERRUPTED_STATUS
        assert not Path(f"/proc/{child_pid}").exists()


def test_monitor_failure_reaps_capture(tmp_path: Path) -> None:
    """A device-monitor error cannot leave an unsupervised capture process."""
    camera(tmp_path)
    with running(tmp_path, ignore_stop=True) as (process, event):
        child_pid = ready(process)
        os.write(event, b"E")
        process.wait(timeout=3)
        _output, error = finish(process)
        assert process.returncode == 1
        assert b"fixture monitor failed" in error
        assert not Path(f"/proc/{child_pid}").exists()


def test_camera_snapshot_ignores_local_nodes_and_missing_attributes(
    tmp_path: Path,
) -> None:
    """Only the remote selected GUID counts as present."""
    spec = importlib.util.spec_from_file_location("minidv_supervisor", SOURCE)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    local = camera(tmp_path, "fw0")
    (local / "is_local").write_text("1\n")
    (tmp_path / "fw1").mkdir()
    assert not module.camera_present(tmp_path, "aabb")
    camera(tmp_path, "fw8", "0xAABB")
    assert module.camera_present(tmp_path, "aabb")


def test_disconnect_kills_an_unresponsive_capture(tmp_path: Path) -> None:
    """Camera removal has a bounded TERM grace period even if dvgrab hangs."""
    device = camera(tmp_path)
    with running(tmp_path, ignore_stop=True) as (process, event):
        child_pid = ready(process)
        shutil.rmtree(device)
        os.write(event, b"remove")
        output, error = finish(process)
        assert output == b"signal=15\n"
        assert b"force-stopping" in error
        assert process.returncode == 1
        assert not Path(f"/proc/{child_pid}").exists()


def test_child_exit_is_reported_without_a_device_event(tmp_path: Path) -> None:
    """The pidfd wakes the supervisor when capture dies with a signal."""
    camera(tmp_path)
    with running(tmp_path) as (process, _event):
        child_pid = ready(process)
        os.kill(child_pid, signal.SIGKILL)
        finish(process)
        assert process.returncode == 128 + signal.SIGKILL
        assert (tmp_path / "snapshots").read_text() == "snapshot\n"
        assert not (tmp_path / "camera-disconnected").exists()
