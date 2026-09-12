"""Exercise wallpaper admission through the rendered rotation command."""

import json
import os
import shlex
import shutil
import subprocess  # ruff: ignore[suspicious-subprocess-import] - isolated command fixtures
import tempfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]


def _chooser_action(
    name: str,
    width: int,
    height: int,
    orientation: str = "TopLeft",
    *,
    current: bool = False,
) -> str:
    bash = shutil.which("bash")
    assert bash is not None
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        library = root / "wallpapers"
        library.mkdir()
        candidate = library / name
        candidate.write_bytes(b"fixture")
        if current:
            (root / "state").mkdir()
            (root / "state/current").write_text(str(candidate), encoding="utf-8")
        binaries = root / "bin"
        binaries.mkdir()
        # The decoder boundary reports fixture geometry; no Wayland session.
        (binaries / "magick").write_text(
            f'#!/bin/sh\nprintf "{width} {height} {orientation}\\n"\n'
        )
        (binaries / "awww").write_text(
            f'#!/bin/sh\nprintf "%s\\n" "$@" > {shlex.quote(str(root / "displayed"))}\n'
        )
        for binary in binaries.iterdir():
            binary.chmod(0o700)
        config = root / "config.json"
        config.write_text(json.dumps({"connections": {"wikimediaCommons": True}}))
        (Path(str(candidate) + ".json")).write_text(
            json.dumps({
                "metadata": {"Categories": {"value": "Featured pictures of mountains"}}
            }),
            encoding="utf-8",
        )
        policy = " ".join(
            shlex.quote(str(value))
            for value in [
                shutil.which("python3"),
                ROOT / "modules/home/desktop/scripts/wallpaper-policy.py",
                "--catalog",
                ROOT / "modules/home/desktop/wallpaper-catalog.json",
                "--config",
                config,
                "--preferences",
                root / "preferences.json",
            ]
        )
        replacements = {
            "bash": bash,
            "runtimePath": str(binaries) + ":" + os.environ["PATH"],
            "wallpaperDirectory": shlex.quote(str(library)),
            "stateDirectory": shlex.quote(str(root / "state")),
            "awwwOutputs": "",
            "transition": "fade",
            "transitionDuration": "0.8",
            "transitionFps": "30",
            "minWidth": "3840",
            "minHeight": "2160",
            "minAspectRatioScaled": "1770",
            "maxAspectRatioScaled": "1790",
            "policyCommand": policy,
        }
        script = (
            ROOT / "modules/home/desktop/scripts/wallpaper-next.sh.in"
        ).read_text()
        for key, value in replacements.items():
            script = script.replace("@" + key + "@", value)
        command = root / "next.sh"
        command.write_text(script)
        subprocess.run(["bash", str(command)], check=True, capture_output=True)  # ruff: ignore[subprocess-without-shell-equals-true, start-process-with-partial-path] - isolated command fixture
        displayed = root / "displayed"
        if not displayed.exists():
            return ""
        arguments = displayed.read_text(encoding="utf-8").splitlines()
        return "blank" if arguments[-1] == "0x000000" else arguments[0]


def _run_chooser(
    name: str, width: int, height: int, orientation: str = "TopLeft"
) -> bool:
    return _chooser_action(name, width, height, orientation) == "img"


@pytest.mark.parametrize(
    ("width", "height"), [(4000, 4000), (6000, 4000), (8000, 2500), (1920, 1080)]
)
def test_rejects_wrong_geometry(width: int, height: int) -> None:
    """Square, camera-ratio, ultrawide and small files never reach the renderer."""
    assert not _run_chooser("landscape.jpg", width, height)


@pytest.mark.parametrize(
    "prefix", ["cma-", "smithsonian-", "nasa-image-library-", "nasa-svs-"]
)
def test_rejects_disabled_source(prefix: str) -> None:
    """Retiring a source also removes its old files from rotation."""
    assert not _run_chooser(prefix + "old.jpg", 3840, 2160)


def test_displays_4k_landscape() -> None:
    """An admitted landscape reaches the actual renderer command boundary."""
    assert _run_chooser("wikimedia-commons-scenic.jpg", 3840, 2160)


def test_rejects_exif_portrait() -> None:
    """A portrait stored sideways does not qualify as a landscape."""
    assert not _run_chooser("portrait.jpg", 3840, 2160, "RightTop")


def test_clears_last_disabled_wallpaper() -> None:
    """A disabled current image does not remain visible when no replacement qualifies."""
    assert _chooser_action("cma-old.jpg", 3840, 2160, current=True) == "blank"


def test_empty_rotation_always_persists_blank() -> None:
    """A second empty rotation still overwrites the renderer's restore cache."""
    assert _chooser_action("cma-old.jpg", 3840, 2160, current=False) == "blank"
