"""Check song-change popups in a live Noctalia/Hyprland session.

Run with Spotify playing as the active media player and leave the desktop idle.
This advances one song and briefly displays a volume OSD without changing volume.

    nix develop --command env PYTHONPATH=tests python3 tests/noctalia/check_media_osd.py
"""

import json
import shutil
import subprocess  # ruff: ignore[suspicious-subprocess-import] -- Calls local desktop tools without a shell.
import sys

from hyprland.compositor_events import CompositorEvents
from notification_process import run as run_command


def _run(*args: str) -> str:
    executable = shutil.which(args[0])
    if executable is None:
        sys.exit(f"Required executable missing: {args[0]}")
    return run_command(
        [executable, *args[1:]],
        text=True,
        stderr=subprocess.DEVNULL,
        timeout=10,
        stdout=subprocess.PIPE,
        check=True,
    ).stdout.strip()


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def _surfaces(changes: CompositorEvents) -> set[str]:
    outputs = json.loads(changes.command("hyprctl", "layers", "-j"))
    return {
        layer["namespace"]
        for output in outputs.values()
        for layers in output["levels"].values()
        for layer in layers
    }


def _observe(changes: CompositorEvents) -> set[str]:
    seen = _surfaces(changes)

    def layer_opened(event: str) -> None:
        kind, _, namespace = event.partition(">>")
        if kind == "openlayer":
            seen.add(namespace)

    changes.observe(layer_opened, timeout=4)
    return seen


def _check(changes: CompositorEvents) -> None:
    """Prove that volume feedback works but a song change opens no popup."""
    _require(
        _run("playerctl", "-p", "spotify", "status") == "Playing",
        "Spotify must be playing",
    )
    _require(
        "noctalia-bar-default" in _surfaces(changes), "Noctalia bar is not visible"
    )
    _run("noctalia", "msg", "volume-osd", "50")
    _require(
        "noctalia-osd" in _observe(changes),
        "Positive control failed: volume OSD did not appear",
    )
    changes.wait(lambda: "noctalia-osd" not in _surfaces(changes), timeout=8)

    before = _run("playerctl", "-p", "spotify", "metadata", "mpris:trackid")
    _run("playerctl", "-p", "spotify", "next")
    seen = _observe(changes)
    after = _run("playerctl", "-p", "spotify", "metadata", "mpris:trackid")
    _require(before != after, "Spotify did not change tracks")
    _require("noctalia-osd" not in seen, "FAIL: a song change opens noctalia-osd")
    _require(
        "noctalia-notification" not in seen, "FAIL: a song change opens a notification"
    )
    sys.stdout.write(
        "PASS: Spotify changed tracks without a popup; volume OSD still works\n"
    )


def main() -> None:
    """Subscribe before dispatching actions so brief popups are retained."""
    with CompositorEvents() as changes:
        _check(changes)


if __name__ == "__main__":
    main()
