"""Exercise native inhibitor policy through the helper's command interface."""

import json
import os
import re
import sys
from pathlib import Path

import pytest
from notification_process import run as run_command

HELPER = (
    Path(__file__).resolve().parents[2]
    / "modules/home/desktop/scripts/idle_inhibit_check.py"
)


@pytest.mark.parametrize(
    ("clients", "screen", "suspend"),
    [
        ([], 0, 0),
        ([{"class": "chatgpt", "inhibitingIdle": True}], 0, 1),
        ([{"class": "chatgpt", "inhibitingIdle": False}], 0, 0),
        ([{"class": "mpv", "inhibitingIdle": True}], 1, 1),
        ([{"class": "zen-beta", "inhibitingIdle": True}], 1, 1),
        (
            [
                {"class": "chatgpt", "inhibitingIdle": True},
                {"class": "mpv", "inhibitingIdle": True},
            ],
            1,
            1,
        ),
        ([{"class": "chatgpt-other", "inhibitingIdle": True}], 1, 1),
        ({"error": "bad response"}, 0, 1),
        ([{"class": "chatgpt"}], 0, 1),
        ([{"class": "chatgpt", "inhibitingIdle": "false"}], 0, 1),
    ],
)
def test_native_inhibitors(
    tmp_path: Path, clients: object, screen: int, suspend: int
) -> None:
    """Only background app native inhibitors may bypass screen protection."""
    executable = tmp_path / "hyprctl"
    executable.write_text(
        re.sub(
            r"__fixture_[0-9]+__",
            lambda match: {
                "__fixture_0__": f"{sys.executable}",
                "__fixture_1__": f"{json.dumps(clients)!r}",
            }[match[0]],
            (Path(__file__).with_name("fixtures") / "hyprctl_clients.py.in").read_text(
                encoding="utf-8"
            ),
        )
    )
    executable.chmod(0o755)
    for action, expected in (("screen", screen), ("suspend", suspend)):
        result = run_command(
            [sys.executable, str(HELPER), action, "chatgpt"],
            env={**os.environ, "PATH": str(tmp_path)},
            capture_output=True,
            text=True,
            check=False,
            timeout=5,
        )
        assert result.returncode == expected, result.stderr


@pytest.mark.parametrize("failure", ["missing", "exit", "malformed", "timeout"])
def test_ipc_failure(tmp_path: Path, failure: str) -> None:
    """Unknown state allows locking but does not risk suspending background work."""
    if failure != "missing":
        executable = tmp_path / "hyprctl"
        executable.write_text(
            (Path(__file__).with_name("fixtures") / "hyprctl_failure.py.in")
            .read_text(encoding="utf-8")
            .replace("__interpreter__", sys.executable)
            .replace("__failure__", repr(failure))
        )
        executable.chmod(0o755)
    for action, expected in (("screen", 0), ("suspend", 1)):
        result = run_command(
            [sys.executable, str(HELPER), action, "chatgpt"],
            env={**os.environ, "PATH": str(tmp_path)},
            capture_output=True,
            text=True,
            check=False,
            timeout=5,
        )
        assert result.returncode == expected
        assert "Cannot inspect native idle inhibitors" in result.stderr
