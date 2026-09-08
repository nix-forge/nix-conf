"""Check the real Ghostty screen after idle Bash startup, a command, and redraw.

Requires Linux, Ghostty, Xvfb, and xdotool. Pass a built Home Manager .bashrc
and its evaluated shell-integration setting. The test uses a private X server
and temporary home, so it cannot type into an existing window or save history
in the user's home. F12 only exports the screen; it sends no input to Bash.
"""

import argparse
import os
import select
import subprocess  # ruff: ignore[suspicious-subprocess-import] -- Runs selected local test tools.
import sys
import tempfile
import time
from pathlib import Path
from typing import TextIO


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def _stop(process: subprocess.Popen | None) -> None:
    if process is not None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


def _check(args: argparse.Namespace, root: Path, log: TextIO) -> None:  # ruff: ignore[too-many-statements] -- Keep the X server and terminal cleanup in the same lifecycle.
    env = dict(os.environ)
    for key in (
        "GHOSTTY_RESOURCES_DIR",
        "GHOSTTY_SHELL_INTEGRATION",
        "GHOSTTY_BASH_INJECT",
        "GHOSTTY_BASH_RCFILE",
        "ENV",
        "BASH_ENV",
    ):
        env.pop(key, None)
    env.update(HOME=str(root), TMPDIR=str(root), GDK_BACKEND="x11")
    for name in ("CONFIG", "CACHE", "DATA", "STATE"):
        env[f"XDG_{name}_HOME"] = str(root / name.lower())
    if args.starship_config:
        env["STARSHIP_CONFIG"] = str(args.starship_config.resolve())

    xserver = terminal = None
    readfd, writefd = os.pipe()
    try:
        xserver = subprocess.Popen(  # ruff: ignore[subprocess-without-shell-equals-true] -- Argument lists use caller-selected local test tools, without a shell.
            [
                args.xvfb,
                "-displayfd",
                str(writefd),
                "-screen",
                "0",
                "1000x700x24",
                "-nolisten",
                "tcp",
            ],
            pass_fds=(writefd,),
            stdout=log,
            stderr=log,
        )
        os.close(writefd)
        writefd = None
        _require(
            bool(select.select([readfd], [], [], 10)[0]),
            "Xvfb did not start within 10 seconds",
        )
        env["DISPLAY"] = ":" + os.read(readfd, 100).decode().strip()
        terminal = subprocess.Popen(  # ruff: ignore[subprocess-without-shell-equals-true] -- Argument lists use caller-selected local test tools, without a shell.
            [
                args.ghostty,
                "--config-default-files=false",
                f"--shell-integration={args.shell_integration}",
                "--shell-integration-features=no-ssh-terminfo",
                "--gtk-single-instance=false",
                "--linux-cgroup=never",
                "--title=Ghostty prompt regression",
                "--keybind=f12=write_screen_file:copy",
                f"--working-directory={root}",
                "-e",
                args.bash,
                "--noprofile",
                "--rcfile",
                str(args.bashrc.resolve()),
                "-i",
            ],
            env=env,
            stdout=log,
            stderr=log,
        )

        def xdo(*command: str) -> str:
            return subprocess.check_output(  # ruff: ignore[subprocess-without-shell-equals-true] -- Talks only to our private X server.
                [args.xdotool, *command],
                env=env,
                timeout=10,
            ).decode()

        window = xdo(
            "search", "--sync", "--name", "Ghostty prompt regression"
        ).splitlines()[0]
        xdo("windowfocus", window)

        def snapshot(label: str, expected: int) -> str:
            old = set(root.glob("*/screen.txt"))
            xdo("key", "F12")
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                created = set(root.glob("*/screen.txt")) - old
                if created:
                    screen = created.pop().read_text()
                    count = screen.count(args.prompt)
                    message = f"{label}: expected {expected} visible prompts, got {count}: {screen!r}"
                    _require(count == expected, message)
                    sys.stdout.write(f"PASS {label}: {count} visible prompt(s)\n")
                    return screen
                time.sleep(0.05)
            message = f"{label}: Ghostty did not export its screen"
            raise AssertionError(message)

        time.sleep(args.settle)
        snapshot("idle startup", 1)
        # A second capture catches a delayed duplicate without shell input.
        time.sleep(1)
        snapshot("continued idle", 1)
        xdo("type", "--clearmodifiers", "--delay", "1", "printf GHOSTTY_OUTPUT")
        xdo("key", "Return")
        time.sleep(1)
        screen = snapshot("output without trailing newline", 2)
        expected_output_copies = 2  # The typed command and its output.
        _require(
            screen.count("GHOSTTY_OUTPUT") == expected_output_copies,
            "Command output was not rendered",
        )
        xdo("key", "ctrl+l")
        time.sleep(0.5)
        snapshot("Ctrl-L redraw", 1)
    finally:
        if writefd is not None:
            os.close(writefd)
        os.close(readfd)
        _stop(terminal)
        _stop(xserver)


def main() -> None:
    """Run the screen checks in a temporary home and private X server."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bashrc", type=Path, required=True)
    parser.add_argument("--starship-config", type=Path)
    parser.add_argument(
        "--shell-integration", choices=("detect", "none"), required=True
    )
    parser.add_argument("--prompt", default="\u276f")
    parser.add_argument("--settle", type=float, default=3)
    for name in ("ghostty", "bash", "xvfb", "xdotool"):
        parser.add_argument(f"--{name}", default="Xvfb" if name == "xvfb" else name)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="ghostty-prompt-test-") as directory:
        root = Path(directory)
        with (root / "terminal.log").open("w+") as log:
            _check(args, root, log)


if __name__ == "__main__":
    main()
