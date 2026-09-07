"""Check song-change popups in a live Noctalia/Hyprland session.

Run with Spotify playing as the active media player and leave the desktop idle.
This advances one song and briefly displays a volume OSD without changing volume.

    python3 tests/noctalia/check_media_osd.py
"""

import json
import shutil
import subprocess  # ruff: ignore[suspicious-subprocess-import] -- Calls local desktop tools without a shell.
import sys
import time


def _run(*args: str) -> str:
    executable = shutil.which(args[0])
    if executable is None:
        sys.exit(f"Required executable missing: {args[0]}")
    return subprocess.check_output(  # ruff: ignore[subprocess-without-shell-equals-true] -- Uses an argument vector and resolved executable.
        [executable, *args[1:]], text=True, stderr=subprocess.DEVNULL, timeout=10
    ).strip()


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def _surfaces() -> set[str]:
    outputs = json.loads(_run("hyprctl", "layers", "-j"))
    return {
        layer["namespace"]
        for output in outputs.values()
        for layers in output["levels"].values()
        for layer in layers
    }


def _observe() -> set[str]:
    seen: set[str] = set()
    deadline = time.monotonic() + 4
    while time.monotonic() < deadline:
        seen.update(_surfaces())
        time.sleep(0.1)
    return seen


def main() -> None:
    """Prove that volume feedback works but a song change opens no popup."""
    _require(
        _run("playerctl", "-p", "spotify", "status") == "Playing",
        "Spotify must be playing",
    )
    _require("noctalia-bar-default" in _surfaces(), "Noctalia bar is not visible")
    _run("noctalia", "msg", "volume-osd", "50")
    _require(
        "noctalia-osd" in _observe(),
        "Positive control failed: volume OSD did not appear",
    )
    deadline = time.monotonic() + 8
    while "noctalia-osd" in _surfaces() and time.monotonic() < deadline:
        time.sleep(0.1)
    _require("noctalia-osd" not in _surfaces(), "An existing OSD did not close")

    before = _run("playerctl", "-p", "spotify", "metadata", "mpris:trackid")
    _run("playerctl", "-p", "spotify", "next")
    seen = _observe()
    after = _run("playerctl", "-p", "spotify", "metadata", "mpris:trackid")
    _require(before != after, "Spotify did not change tracks")
    _require("noctalia-osd" not in seen, "FAIL: a song change opens noctalia-osd")
    _require(
        "noctalia-notification" not in seen, "FAIL: a song change opens a notification"
    )
    sys.stdout.write(
        "PASS: Spotify changed tracks without a popup; volume OSD still works\n"
    )


if __name__ == "__main__":
    main()
