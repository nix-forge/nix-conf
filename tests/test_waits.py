"""Exercise fixture readiness races and bounded process completion."""

from __future__ import annotations

import os
import subprocess  # ruff: ignore[suspicious-subprocess-import] -- Owned disposable interpreter only.
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from threading import Event

import pytest
from waits import FileChanges, wait_child, wait_file


def test_existing_marker_needs_no_future_event(tmp_path: Path) -> None:
    """A marker written before subscription establishes readiness immediately."""
    marker = tmp_path / "ready"
    marker.touch()
    wait_file(marker)


def test_change_during_snapshot_is_retained(tmp_path: Path) -> None:
    """A notification received before entering the wait cannot be lost."""
    inspected = Event()
    changed = Event()
    marker = tmp_path / "ready"

    def snapshot() -> bool:
        present = marker.exists()
        if not present:
            inspected.set()
            assert changed.wait(5)
        return present

    with ThreadPoolExecutor(max_workers=1) as executor:
        waiter = executor.submit(FileChanges(tmp_path).wait, snapshot)
        assert inspected.wait(5)
        marker.touch()
        changed.set()
        waiter.result(timeout=5)


def test_unchanged_state_is_inspected_once() -> None:
    """Expiration must not generate timer-driven predicate calls."""
    snapshots = []

    def absent() -> bool:
        snapshots.append(False)
        return False

    with pytest.raises(TimeoutError):
        # Newly created directories produce real delayed Darwin notifications.
        # This existing source directory stays unchanged during the idle wait.
        FileChanges(Path(__file__).parent / "process/fixtures").wait(absent, 0.05)
    assert snapshots == [False]


def test_snapshot_cannot_pass_after_deadline(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A slow state read must not turn deadline expiry into a successful wait."""
    clock = iter([0.0, 2.0])
    monkeypatch.setattr("waits.monotonic", lambda: next(clock))
    with pytest.raises(TimeoutError):
        FileChanges(tmp_path).wait(lambda: True, timeout=1)


@pytest.mark.skipif(not hasattr(os, "pidfd_open"), reason="Linux child supervision")
def test_child_exit_and_deadline_are_owned(tmp_path: Path) -> None:
    """Timeout retains a live child; exit notification permits its reaping."""
    child = subprocess.Popen(  # ruff: ignore[subprocess-without-shell-equals-true] -- Runs the repository-owned native child fixture.
        [
            sys.executable,
            str(Path(__file__).parent / "process/fixtures/command.py"),
            "closed-pipes",
        ],
        cwd=tmp_path,
    )
    try:
        with pytest.raises(subprocess.TimeoutExpired):
            wait_child(child, 0.05)
        assert child.returncode is None
        child.terminate()
        assert wait_child(child) < 0
    finally:
        if child.returncode is None:
            child.kill()
            child.wait()
