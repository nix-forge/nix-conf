"""Keep remembered login sessions usable across system generations."""

from __future__ import annotations

import shutil
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Exercise the helper in disposable cache directories.
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "modules/nixos/display-managers/scripts/prepare-tuigreet-cache.sh"


@pytest.fixture
def cache_layout(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> tuple[Path, Path]:
    """Create desktop entries independently of the host's installed sessions.

    Returns:
        Paths for the disposable cache and session root.

    """
    monkeypatch.delenv("BASH_ENV", raising=False)
    monkeypatch.delenv("ENV", raising=False)
    session_root = tmp_path / "sessions"
    wayland = session_root / "share/wayland-sessions"
    wayland.mkdir(parents=True)
    for name in ("hyprland-uwsm.desktop", "gnome.desktop"):
        (wayland / name).write_text(
            "[Desktop Entry]\nType=Application\nName=Test session\nExec=true\n",
            encoding="utf-8",
        )
    return tmp_path / "cache", session_root


def _prepare(cache: Path, session_root: Path) -> None:
    """Run the actual helper with its generated wrapper's strict shell flags."""
    bash = shutil.which("bash")
    if bash is None:
        pytest.fail("Bash is required to run the cache helper")
    result = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Fixed script and disposable paths, without a shell.
        [
            bash,
            "-euo",
            "pipefail",
            str(SCRIPT),
            str(cache),
            str(session_root),
            "hyprland-uwsm.desktop",
            "alice",
        ],
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )
    assert result.returncode == 0, result.stderr


def test_fresh_cache_seeds_sole_user_and_default_session(
    cache_layout: tuple[Path, Path],
) -> None:
    """Remember the sole account and its default desktop on first use."""
    cache, session_root = cache_layout
    _prepare(cache, session_root)

    assert (cache / "lastuser").read_text(encoding="utf-8") == "alice"
    assert (cache / "lastsession-path-alice").read_text(encoding="utf-8") == str(
        session_root / "share/wayland-sessions/hyprland-uwsm.desktop"
    )


def test_stale_store_path_resolves_to_current_session(
    cache_layout: tuple[Path, Path],
) -> None:
    """Repair an old generation path while preserving the chosen desktop."""
    cache, session_root = cache_layout
    cache.mkdir()
    selected = cache / "lastsession-path-alice"
    selected.write_text(
        "/nix/store/old-generation-desktops/share/wayland-sessions/gnome.desktop",
        encoding="utf-8",
    )
    _prepare(cache, session_root)

    assert selected.read_text(encoding="utf-8") == str(
        session_root / "share/wayland-sessions/gnome.desktop"
    )


def test_valid_manual_gnome_selection_is_retained(
    cache_layout: tuple[Path, Path],
) -> None:
    """Keep a manually chosen current session instead of resetting to default."""
    cache, session_root = cache_layout
    cache.mkdir()
    selected = cache / "lastsession-path-alice"
    choice = str(session_root / "share/wayland-sessions/gnome.desktop")
    selected.write_text(choice, encoding="utf-8")
    _prepare(cache, session_root)

    assert selected.read_text(encoding="utf-8") == choice


@pytest.mark.parametrize(
    "remembered",
    ["", "/nix/store/removed-desktops/share/xsessions/removed.desktop"],
    ids=["empty-selection", "removed-session"],
)
def test_unavailable_selection_falls_back_to_hyprland_uwsm(
    cache_layout: tuple[Path, Path], remembered: str
) -> None:
    """Recover an empty or removed desktop selection using the default."""
    cache, session_root = cache_layout
    cache.mkdir()
    selected = cache / "lastsession-path-alice"
    selected.write_text(remembered, encoding="utf-8")
    _prepare(cache, session_root)

    assert selected.read_text(encoding="utf-8") == str(
        session_root / "share/wayland-sessions/hyprland-uwsm.desktop"
    )


def test_custom_command_remains_without_session_path(
    cache_layout: tuple[Path, Path],
) -> None:
    """Preserve a deliberate command instead of replacing it with a desktop."""
    cache, session_root = cache_layout
    cache.mkdir()
    command = cache / "lastsession-alice"
    custom = "custom-compositor --test-option"
    command.write_text(custom, encoding="utf-8")
    _prepare(cache, session_root)

    assert command.read_text(encoding="utf-8") == custom
    assert not (cache / "lastsession-path-alice").exists()
