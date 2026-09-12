"""Exercise native inhibitor policy through the helper's command interface."""

import json
import os
import subprocess  # ruff: ignore[suspicious-subprocess-import] - invoke the helper against a local fixture
import sys
from pathlib import Path

import pytest

HELPER = (
    Path(__file__).resolve().parents[2]
    / "modules/home/desktop/scripts/idle-inhibit-check.py"
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
        f"#!{sys.executable}\nimport sys\n"
        "assert sys.argv[1:] == ['-j', 'clients']\n"
        f"print({json.dumps(clients)!r})\n"
    )
    executable.chmod(0o755)
    for action, expected in (("screen", screen), ("suspend", suspend)):
        result = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - fixed helper and test fixture arguments
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
        body = {
            "exit": "raise SystemExit(1)",
            "malformed": "print('not JSON')",
            "timeout": "import time; time.sleep(10)",
        }[failure]
        executable.write_text(f"#!{sys.executable}\n{body}\n")
        executable.chmod(0o755)
    for action, expected in (("screen", 0), ("suspend", 1)):
        result = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - fixed helper and test fixture arguments
            [sys.executable, str(HELPER), action, "chatgpt"],
            env={**os.environ, "PATH": str(tmp_path)},
            capture_output=True,
            text=True,
            check=False,
            timeout=5,
        )
        assert result.returncode == expected
        assert "Cannot inspect native idle inhibitors" in result.stderr
