"""Exercise process-group cleanup for an exited leader and cancellation."""

from __future__ import annotations

import os
import select
import signal
import sys
from contextlib import ExitStack
from pathlib import Path

import pytest
from vscode import probe_process
from waits import wait_file


@pytest.fixture
def native_probe(monkeypatch: pytest.MonkeyPatch) -> None:
    """Exercise POSIX ownership using the native application-bundle branch."""
    monkeypatch.setattr(probe_process.sys, "platform", "darwin")
    monkeypatch.setattr(probe_process, "_native_code", lambda executable: executable)


def _run_failure(
    root: Path, stack: ExitStack, descriptors: list[int], mode: str
) -> None:
    """Subscribe to descendant exit before testing ownership cancellation.

    Raises:
        RuntimeError: The fixture intentionally fails startup.

    """
    marker = root / "child"
    fixture = Path(__file__).resolve().parents[1] / "process/fixtures/command.py"
    with probe_process.owned_probe(
        root, [sys.executable, str(fixture), "closed-descendant", str(marker)]
    ):
        wait_file(marker, timeout=5)
        descriptor = os.pidfd_open(int(marker.read_text(encoding="utf-8")))
        stack.callback(os.close, descriptor)
        descriptors.append(descriptor)
        if mode == "signal":
            os.kill(os.getpid(), signal.SIGTERM)
        message = "startup failed"
        raise RuntimeError(message)


@pytest.mark.usefixtures("native_probe")
@pytest.mark.skipif(sys.platform != "linux", reason="Native Linux pidfd evidence")
@pytest.mark.parametrize(
    ("mode", "expected"), [("startup", RuntimeError), ("signal", SystemExit)]
)
def test_cancellation_cleans_descendants_and_restores_handler(
    tmp_path: Path, mode: str, expected: type[BaseException]
) -> None:
    """An exited launcher cannot release its surviving application's ownership."""
    previous = signal.getsignal(signal.SIGTERM)
    descriptors: list[int] = []
    with ExitStack() as stack:
        with pytest.raises(expected):
            _run_failure(tmp_path, stack, descriptors, mode)
        assert signal.getsignal(signal.SIGTERM) == previous
        assert select.select(descriptors, [], [], 5)[0] == descriptors


def _missing(root: Path) -> None:
    with probe_process.owned_probe(root, [str(root / "missing-code")]):
        pytest.fail("A missing executable cannot yield ownership")


@pytest.mark.usefixtures("native_probe")
def test_failed_spawn_restores_handlers(tmp_path: Path) -> None:
    """Launch failures do not require a PID or leak cancellation handlers."""
    previous = signal.getsignal(signal.SIGTERM)
    with pytest.raises(FileNotFoundError):
        _missing(tmp_path)
    assert signal.getsignal(signal.SIGTERM) == previous
