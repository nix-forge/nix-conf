"""Private D-Bus fixtures for isolated service notification tests."""

from __future__ import annotations

import shutil
import subprocess  # ruff: ignore[suspicious-subprocess-import]
from typing import TYPE_CHECKING

import pytest
from notification_process import wait_child

if TYPE_CHECKING:
    from collections.abc import Iterator
    from pathlib import Path


@pytest.fixture
def private_bus(tmp_path: Path) -> Iterator[str]:
    """Start a private bus without contacting the host's service bus.

    Yields:
        The private bus address.

    """
    daemon = shutil.which("dbus-daemon")
    assert daemon is not None, "dbus-daemon is required"
    config = tmp_path / "bus.conf"
    config.write_text(
        "<busconfig><type>session</type><listen>unix:tmpdir=/tmp</listen>"
        '<auth>EXTERNAL</auth><policy context="default">'
        '<allow own="*"/><allow send_destination="*"/><allow receive_sender="*"/>'
        "</policy></busconfig>",
        encoding="utf-8",
    )
    with subprocess.Popen(  # ruff: ignore[subprocess-without-shell-equals-true] - Fixed executable, no shell input.
        [daemon, f"--config-file={config}", "--nofork", "--print-address=1"],
        stdout=subprocess.PIPE,
        text=True,
    ) as process:
        try:
            assert process.stdout is not None
            address = process.stdout.readline().strip()
            assert address.startswith("unix:"), "private D-Bus daemon did not start"
            yield address
        finally:
            process.terminate()
            wait_child(process, timeout=5)
