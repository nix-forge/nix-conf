"""Exercise bookmark reconciliation through its installed command interface."""

from __future__ import annotations

import json
import subprocess  # ruff: ignore[suspicious-subprocess-import]
import sys
from pathlib import Path
from typing import TYPE_CHECKING

import pytest
from defusedxml import ElementTree

if TYPE_CHECKING:
    from collections.abc import Callable

SCRIPT = Path(__file__).parents[2] / "modules/home/xdg/sync_directory_bookmarks.py"


@pytest.fixture
def run_sync(tmp_path: Path) -> Callable[..., subprocess.CompletedProcess[str]]:
    """Provide an isolated CLI with one existing and one missing directory.

    Returns:
        A caller for the real reconciliation command.

    """
    directory = tmp_path / "My Projects #1"
    directory.mkdir()
    policy = tmp_path / "policy.json"
    policy.write_text(
        json.dumps([
            {"path": str(directory), "label": "Projects"},
            {"path": str(tmp_path / "missing"), "label": "Missing"},
            {"path": str(directory), "label": "Duplicate"},
        ]),
        encoding="utf-8",
    )

    def invoke(*arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true]
            [
                sys.executable,
                str(SCRIPT),
                "--config",
                str(policy),
                "--home",
                str(tmp_path),
                "--config-home",
                str(tmp_path / "config"),
                "--data-home",
                str(tmp_path / "data"),
                *arguments,
            ],
            capture_output=True,
            text=True,
            check=False,
        )

    return invoke


def test_create_escape_and_repeat(
    tmp_path: Path, run_sync: Callable[..., subprocess.CompletedProcess[str]]
) -> None:
    """Add existing directories once with valid escaped URIs and writable files."""
    result = run_sync()
    assert result.returncode == 0, result.stderr
    gtk = tmp_path / "config/gtk-3.0/bookmarks"
    kde = tmp_path / "data/user-places.xbel"
    assert gtk.read_text() == f"{tmp_path.as_uri()}/My%20Projects%20%231 Projects\n"
    root = ElementTree.parse(kde).getroot()
    assert [item.get("href") for item in root.findall("bookmark")] == [
        f"{tmp_path.as_uri()}/My%20Projects%20%231"
    ]
    assert root.find("info") is None  # KIO must initialize native places itself.
    original = [(path.read_bytes(), path.stat().st_mtime_ns) for path in (gtk, kde)]
    assert run_sync().returncode == 0
    assert [
        (path.read_bytes(), path.stat().st_mtime_ns) for path in (gtk, kde)
    ] == original
    assert oct(gtk.stat().st_mode & 0o777) == "0o600"


def test_preserve_custom_entries_and_kde_metadata(
    tmp_path: Path, run_sync: Callable[..., subprocess.CompletedProcess[str]]
) -> None:
    """Keep remote bookmarks, custom labels, separators and hidden state."""
    gtk = tmp_path / "config/gtk-3.0/bookmarks"
    kde = tmp_path / "data/user-places.xbel"
    gtk.parent.mkdir(parents=True)
    kde.parent.mkdir(parents=True)
    original = f"sftp://example.org/shared Shared\nfile://localhost{tmp_path}/My%20Projects%20%231/ My label".encode()
    gtk.write_bytes(original)
    gtk.chmod(0o640)
    kde.write_text(
        '<!DOCTYPE xbel><xbel version="1.0" xmlns:bookmark="http://www.freedesktop.org/standards/desktop-bookmarks"><info><metadata owner="http://www.kde.org"><kde_places_version>4</kde_places_version></metadata></info><separator/><bookmark href="sftp://example.org/shared"><title>Custom</title><info><metadata owner="http://www.kde.org"><IsHidden>true</IsHidden></metadata><metadata owner="http://freedesktop.org"><bookmark:icon name="folder-remote"/></metadata></info></bookmark></xbel>'
    )
    assert run_sync().returncode == 0
    assert gtk.read_bytes() == original
    assert oct(gtk.stat().st_mode & 0o777) == "0o640"
    root = ElementTree.parse(kde).getroot()
    assert root.find("separator") is not None
    assert root.findtext("info/metadata/kde_places_version") == "4"
    assert root.findtext("bookmark/title") == "Custom"
    assert root.findtext("bookmark/info/metadata/IsHidden") == "true"
    assert '<bookmark:icon name="folder-remote"' in kde.read_text()
    assert "<!DOCTYPE xbel>" in kde.read_text()
    assert [item.findtext("title") for item in root.findall("bookmark")] == [
        "Custom",
        "Projects",
    ]


def test_legacy_migration(
    tmp_path: Path, run_sync: Callable[..., subprocess.CompletedProcess[str]]
) -> None:
    """Retain the GTK fallback when the modern bookmark file is first created."""
    legacy = tmp_path / ".gtk-bookmarks"
    original = b"sftp://example.org/shared Shared\n"
    legacy.write_bytes(original)
    assert run_sync().returncode == 0
    modern = tmp_path / "config/gtk-3.0/bookmarks"
    assert modern.read_bytes().startswith(original)
    assert modern.read_bytes() == legacy.read_bytes()


def test_dry_run_creates_nothing(
    tmp_path: Path, run_sync: Callable[..., subprocess.CompletedProcess[str]]
) -> None:
    """Dry runs do not create locks, folders or bookmark state."""
    assert run_sync("--dry-run").returncode == 0
    assert not (tmp_path / "config").exists()
    assert not (tmp_path / "data").exists()


@pytest.mark.parametrize(
    "content",
    [
        "<broken>",
        "<wrong/>",
        '<!DOCTYPE xbel [<!ENTITY x "expanded">]><xbel>&x;</xbel>',
    ],
)
def test_invalid_xml_preserves_all_bookmarks(
    tmp_path: Path,
    run_sync: Callable[..., subprocess.CompletedProcess[str]],
    content: str,
) -> None:
    """A malformed document or entity expansion aborts before GTK changes."""
    kde = tmp_path / "data/user-places.xbel"
    kde.parent.mkdir()
    kde.write_text(content)
    assert run_sync().returncode != 0
    assert kde.read_text() == content
    assert not (tmp_path / "config/gtk-3.0/bookmarks").exists()


def test_foreign_symlink_is_preserved(
    tmp_path: Path, run_sync: Callable[..., subprocess.CompletedProcess[str]]
) -> None:
    """A separately managed bookmark file cannot be silently replaced."""
    target = tmp_path / "foreign"
    target.write_text("original")
    gtk = tmp_path / "config/gtk-3.0/bookmarks"
    gtk.parent.mkdir(parents=True)
    gtk.symlink_to(target)
    assert run_sync().returncode != 0
    assert gtk.is_symlink()
    assert target.read_text() == "original"
    assert not (tmp_path / "data/user-places.xbel").exists()
