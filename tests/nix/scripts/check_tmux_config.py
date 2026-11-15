"""Parse real generated configuration in a private tmux server."""

import json
import pathlib
import shutil
import subprocess  # ruff: ignore[suspicious-subprocess-import]
import sys

configuration, expected_path, hold_command = sys.argv[1:]
expected = json.loads(pathlib.Path(expected_path).read_text(encoding="utf-8"))
tmux = shutil.which("tmux")
assert tmux is not None
arguments = [tmux, "-S", str(pathlib.Path.cwd() / "tmux.sock")]
try:
    subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Fixed tmux arguments and Nix-built configuration.
        [
            *arguments,
            "-f",
            configuration,
            "new-session",
            "-d",
            "-s",
            "fixture",
            hold_command,
        ],
        check=True,
    )
    for option, value in {
        "set-titles-string": expected["title"],
        "status-left": expected["status"],
        "status-interval": "17",
    }.items():
        output = subprocess.check_output(  # ruff: ignore[subprocess-without-shell-equals-true] - Private server option query.
            [*arguments, "show-options", "-gv", option],
            text=True,
        )
        assert output == value + "\n", (option, output, value)
    injected = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Private server option query.
        [*arguments, "show-options", "-g", "@injected"],
        capture_output=True,
        check=False,
    )
    assert injected.returncode != 0
finally:
    subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Shut down only the private test server.
        [*arguments, "kill-server"],
        check=False,
    )
