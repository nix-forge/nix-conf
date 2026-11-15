"""Exercise preference updates through the sourced Home Manager shell fragment."""

from __future__ import annotations

import json
import os
import re
import shlex
import shutil
import subprocess  # ruff: ignore[suspicious-subprocess-import] - disposable shell fixture
from pathlib import Path

import pytest

SCRIPT = (
    Path(__file__).resolve().parents[2]
    / "modules/home/spotify-assets/configure-spotify-quality.sh"
)
EXPECTED = (
    "unmanaged=a=b\n"
    "audio.play_bitrate_enumeration=3\n"
    "ui.track_notifications_enabled=false\n"
    "audio.play_bitrate_non_metered_enumeration=3\n"
    "audio.allow_downgrade=false\n"
    "app.autostart-configured=true\n"
    'app.autostart-mode="off"\n'
)


def run_update(
    root: Path,
    *,
    running: bool = False,
    failure: str | None = None,
    preferences: dict[str, bool | int | str] | None = None,
) -> subprocess.CompletedProcess[str]:
    """Render pinned-command boundaries against real local files and utilities.

    Returns:
        Sourced command status and diagnostics.

    """
    managed = root / "managed-preferences"
    managed.write_text(
        EXPECTED.split("\n", 1)[1]
        if preferences is None
        else "".join(
            f"{key}={json.dumps(value)}\n" for key, value in sorted(preferences.items())
        )
    )
    replacements = {
        "preferenceUpdater": shlex.quote(
            str(SCRIPT.with_name("update-preferences.awk"))
        ),
        "managedPreferences": shlex.quote(str(managed)),
        "pgrep": shutil.which("true" if running else "false"),
        "spotifyPreferences": shlex.quote(str(root / "prefs"))
        + " "
        + shlex.quote(str(root / "Users"))
        + "/*-user/prefs",
    }
    for command in ("mktemp", "awk", "mv", "rm", "cmp"):
        replacements[command] = shutil.which("false" if failure == command else command)
    bash = shutil.which("bash")
    assert bash is not None
    if failure == "cmp":
        adapter = root / "cmp-error"
        adapter.write_text(
            re.sub(
                r"__fixture_[0-9]+__",
                lambda match: {"__fixture_0__": f"{bash}"}[match[0]],
                (Path(__file__).with_name("fixtures") / "cmp-error.sh.in").read_text(
                    encoding="utf-8"
                ),
            )
        )
        adapter.chmod(0o700)
        replacements["cmp"] = str(adapter)
    if failure != "awk":
        awk = replacements["awk"]
        assert awk is not None
        adapter = root / "count-awk"
        adapter.write_text(
            re.sub(
                r"__fixture_[0-9]+__",
                lambda match: {
                    "__fixture_0__": f"{bash}",
                    "__fixture_1__": f"{shlex.quote(str(root / 'awk-calls'))}",
                    "__fixture_2__": f"{shlex.quote(awk)}",
                }[match[0]],
                (
                    Path(__file__).with_name("fixtures") / "count-awk-calls.sh.in"
                ).read_text(encoding="utf-8"),
            )
        )
        adapter.chmod(0o700)
        replacements["awk"] = str(adapter)
    source = SCRIPT.read_text()
    for name, command in replacements.items():
        assert command is not None
        source = source.replace("@" + name + "@", command)
    rendered = root / "update.sh"
    rendered.write_text(source)
    return subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - source only the rendered fixture
        [bash, "-c", 'source "$1"', "fixture", str(rendered)],
        check=False,
        capture_output=True,
        text=True,
    )


def test_updates_each_profile_once_and_preserves_unmanaged_lines(
    tmp_path: Path,
) -> None:
    """Deduplicate managed keys and append missing ones in stable order."""
    paths = [tmp_path / "prefs", tmp_path / "Users/profile-user/prefs"]
    for path in paths:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            "unmanaged=a=b\naudio.play_bitrate_enumeration=0\n"
            "audio.play_bitrate_enumeration=5\n"
        )
    result = run_update(tmp_path)
    assert result.returncode == 0, result.stderr
    for path in paths:
        assert path.read_text() == EXPECTED
    assert (tmp_path / "awk-calls").read_text() == "xx"
    assert not list(tmp_path.rglob("prefs.tmp.*"))


def test_unchanged_preferences_keep_inode_mtime_and_mode(tmp_path: Path) -> None:
    """A repeated activation does not replace an already correct file."""
    prefs = tmp_path / "prefs"
    prefs.write_text(EXPECTED)
    prefs.chmod(0o640)
    os.utime(prefs, ns=(1000000000, 1000000000))
    before = prefs.stat()
    result = run_update(tmp_path)
    assert result.returncode == 0, result.stderr
    after = prefs.stat()
    assert (after.st_ino, after.st_mtime_ns, after.st_mode) == (
        before.st_ino,
        before.st_mtime_ns,
        before.st_mode,
    )
    assert not list(tmp_path.glob("prefs.tmp.*"))


@pytest.mark.parametrize("command", ["awk", "mktemp", "mv", "cmp"])
def test_failed_update_leaves_original_and_cleans_temporary_files(
    tmp_path: Path, command: str
) -> None:
    """Failure remains visible even when the sourcing shell has no errexit."""
    prefs = tmp_path / "prefs"
    original = "unmanaged=preserve\n"
    prefs.write_text(original)
    result = run_update(tmp_path, failure=command)
    assert result.returncode != 0
    assert prefs.read_text() == original
    assert not list(tmp_path.glob("prefs.tmp.*"))


def test_running_spotify_preserves_preferences(tmp_path: Path) -> None:
    """Never rewrite a running application's preference file."""
    prefs = tmp_path / "prefs"
    prefs.write_text("untouched\n")
    result = run_update(tmp_path, running=True)
    assert result.returncode == 0, result.stderr
    assert prefs.read_text() == "untouched\n"


def test_missing_profiles_are_not_created(tmp_path: Path) -> None:
    """Activation tolerates Spotify not having created a profile yet."""
    result = run_update(tmp_path)
    assert result.returncode == 0, result.stderr
    assert not (tmp_path / "prefs").exists()
    assert not (tmp_path / "Users").exists()


def test_alternative_and_empty_policy_preserve_undeclared_choices(
    tmp_path: Path,
) -> None:
    """Removing managed keys preserves UI choices; declared alternatives apply."""
    prefs = tmp_path / "prefs"
    prefs.write_text(
        'ui.track_notifications_enabled=true\napp.autostart-mode="on"\naudio.play_bitrate_enumeration=3\n'
    )
    result = run_update(tmp_path, preferences={"audio.play_bitrate_enumeration": 4})
    assert result.returncode == 0, result.stderr
    assert (
        prefs.read_text()
        == 'ui.track_notifications_enabled=true\napp.autostart-mode="on"\naudio.play_bitrate_enumeration=4\n'
    )
    before = prefs.stat()
    result = run_update(tmp_path, preferences={})
    assert result.returncode == 0, result.stderr
    assert prefs.stat().st_ino == before.st_ino
    assert prefs.stat().st_mtime_ns == before.st_mtime_ns
