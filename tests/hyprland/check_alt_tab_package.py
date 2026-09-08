"""Run keyboard, ordering, and timing checks against a temporary Hyprshell daemon.

Pass the binary to test. Requires an idle desktop, three ordinary windows,
and /dev/uinput access. The runner restores the normal service and focus.
"""

from __future__ import annotations

import subprocess  # ruff: ignore[suspicious-subprocess-import] -- Explicit local test script arguments.
import sys
from pathlib import Path
from typing import TYPE_CHECKING

from check_alt_tab_ipc_timeout import (
    _check,  # ruff: ignore[import-private-name] -- Shared temporary daemon runner.
    _require,  # ruff: ignore[import-private-name] -- Shared test assertions.
)
from check_alt_tab_timing import (
    _check as _check_timing,  # ruff: ignore[import-private-name] -- Exercise the same timing checks with this keyboard.
)

if TYPE_CHECKING:
    from check_alt_tab_ipc_timeout import _Proxy

CLI_ARGUMENTS = 2


def _exercise(binary: str, env: dict[str, str], _proxy: _Proxy, fd: int) -> None:
    directory = Path(__file__).resolve().parent
    for script, args in (
        ("check_alt_tab_release_race.py", [binary]),
        ("check_alt_tab.py", []),
    ):
        subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] -- Fixed script paths and explicit argv.
            [sys.executable, str(directory / script), *args],
            env=env,
            check=True,
            timeout=90,
        )
    _check_timing(fd)


if __name__ == "__main__":
    _require(len(sys.argv) == CLI_ARGUMENTS, "Pass the Hyprshell binary to test")
    _check(sys.argv[1], _exercise, expected_warnings=0)
