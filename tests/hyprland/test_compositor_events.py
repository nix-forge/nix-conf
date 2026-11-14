"""Notification framing, deadline and snapshot-race regressions."""

from __future__ import annotations

import os
import select
import socket
import subprocess  # ruff: ignore[suspicious-subprocess-import] -- Standard subprocess exceptions only.
import sys
from pathlib import Path

import pytest
from hyprland.compositor_events import CompositorEvents, command_output

pytestmark = pytest.mark.skipif(
    sys.platform != "linux", reason="Hyprland fixtures use Linux process state"
)

EXPECTED_SNAPSHOTS = 2
EXPECTED_FAILURE_STATUS = 7


def test_notification_between_snapshot_and_wait(tmp_path: Path) -> None:
    """A notification arriving during the initial snapshot is retained."""
    path = tmp_path / "events"
    with socket.socket(socket.AF_UNIX) as server:
        server.bind(str(path))
        server.listen(1)
        with CompositorEvents(path) as changes, server.accept()[0] as peer:
            snapshots = 0

            def ready() -> bool:
                nonlocal snapshots
                snapshots += 1
                if snapshots == 1:
                    peer.sendall(b"activewindowv2>>abc\n")
                    return False
                return True

            changes.wait(ready, timeout=1)
            assert snapshots == EXPECTED_SNAPSHOTS


def test_no_timer_driven_snapshots(tmp_path: Path) -> None:
    """An idle subscription takes one snapshot and blocks until its deadline."""
    path = tmp_path / "events"
    with socket.socket(socket.AF_UNIX) as server:
        server.bind(str(path))
        server.listen(1)
        with CompositorEvents(path) as changes, server.accept()[0]:
            snapshots = 0

            def pending() -> bool:
                nonlocal snapshots
                snapshots += 1
                return False

            with pytest.raises(TimeoutError):
                changes.wait(pending, timeout=0.02)
            assert snapshots == 1


def test_closed_stream_fails_instead_of_spinning(tmp_path: Path) -> None:
    """A disconnected producer fails immediately and the descriptor is closed."""
    path = tmp_path / "events"
    with socket.socket(socket.AF_UNIX) as server:
        server.bind(str(path))
        server.listen(1)
        with CompositorEvents(path) as changes:
            peer, _ = server.accept()
            peer.close()
            with pytest.raises(ConnectionError, match="stream closed"):
                changes.wait(lambda: False)
        assert changes.socket.fileno() == -1


def test_slow_snapshot_cannot_pass_after_deadline(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Include the snapshot's own execution time in the overall budget."""
    path = tmp_path / "events"
    clock = iter([0.0, 2.0])
    monkeypatch.setattr("hyprland.compositor_events.monotonic", lambda: next(clock))
    with socket.socket(socket.AF_UNIX) as server:
        server.bind(str(path))
        server.listen(1)
        with CompositorEvents(path) as changes, pytest.raises(TimeoutError):
            changes.wait(lambda: True, timeout=1)


def test_command_output_and_failure() -> None:
    """Capture output and preserve nonzero command status."""
    assert command_output(sys.executable, "-c", "print('ready')") == "ready\n"
    with pytest.raises(subprocess.CalledProcessError) as failure:
        command_output(sys.executable, "-c", "raise SystemExit(7)")
    assert failure.value.returncode == EXPECTED_FAILURE_STATUS


@pytest.mark.timeout(5)
def test_stalled_snapshot_is_killed_and_reaped(tmp_path: Path) -> None:
    """A blocked query shares the observer budget and leaves no owned child."""
    path = tmp_path / "events"
    child_pid = tmp_path / "child-pid"
    with socket.socket(socket.AF_UNIX) as server:
        server.bind(str(path))
        server.listen(1)
        with CompositorEvents(path) as changes, server.accept()[0]:
            with pytest.raises(subprocess.TimeoutExpired):
                changes.wait(
                    lambda: bool(
                        changes.command(
                            sys.executable,
                            str(
                                Path(__file__).resolve().parents[1]
                                / "fixtures/process.py"
                            ),
                            "self-pid-pause",
                            str(child_pid),
                        )
                    ),
                    timeout=0.2,
                )
            assert changes.deadline is None
    pid = int(child_pid.read_text())
    with pytest.raises(ProcessLookupError):
        os.kill(pid, 0)
    with pytest.raises(ChildProcessError):
        os.waitpid(pid, os.WNOHANG)


@pytest.mark.parametrize("leader_exits", [False, True])
@pytest.mark.timeout(5)
def test_timeout_stops_descendants_holding_output(
    tmp_path: Path, leader_exits: bool
) -> None:
    """Drain finishes when an owned descendant inherits the command's stdout."""
    child_pid = tmp_path / "descendant-pid"
    with pytest.raises(subprocess.TimeoutExpired):
        command_output(
            sys.executable,
            str(Path(__file__).resolve().parents[1] / "fixtures/process.py"),
            "spawn-pause",
            str(child_pid),
            "exit" if leader_exits else "wait",
            timeout=0.2,
        )
    # Signal delivery and stream EOF do not prove the descendant has exited.
    # Observe kernel completion rather than taking a racy /proc state snapshot.
    try:
        descriptor = os.pidfd_open(int(child_pid.read_text()))
    except ProcessLookupError:
        return
    try:
        assert select.select([descriptor], [], [], 1)[0]
    finally:
        os.close(descriptor)


def test_observation_retains_brief_layer_changes(tmp_path: Path) -> None:
    """Record a popup even when it closes before a state query could see it."""
    path = tmp_path / "events"
    with socket.socket(socket.AF_UNIX) as server:
        server.bind(str(path))
        server.listen(1)
        with CompositorEvents(path) as changes, server.accept()[0] as peer:
            peer.sendall(b"openlayer>>noctalia-osd\ncloselayer>>noctalia-osd\n")
            events: list[str] = []
            changes.observe(events.append, timeout=0.02)
            assert events == ["openlayer>>noctalia-osd", "closelayer>>noctalia-osd"]
            assert changes.deadline is None


def test_idle_observation_blocks_without_callbacks(tmp_path: Path) -> None:
    """A negative observation expires without querying unchanged state."""
    path = tmp_path / "events"
    with socket.socket(socket.AF_UNIX) as server:
        server.bind(str(path))
        server.listen(1)
        with CompositorEvents(path) as changes, server.accept()[0]:
            events: list[str] = []
            changes.observe(events.append, timeout=0.02)
            assert events == []
