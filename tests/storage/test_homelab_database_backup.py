"""Verify committed WAL data, actual Restic restoration and failed-export safety."""

from __future__ import annotations

import json
import runpy
import shutil
import sqlite3
import subprocess
from pathlib import Path

import pytest

PRIVATE_FILE_MODE = 0o600
PRIVATE_DIRECTORY_MODE = 0o700

HELPER = runpy.run_path(
    str(
        Path(__file__).parents[2]
        / "hosts/nixos/desktop/local/storage/scripts/export_homelab_databases.py"
    )
)


def test_wal_snapshot_restores_from_restic(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Restore committed records that existed only in the live SQLite WAL."""
    restic = shutil.which("restic")
    assert restic is not None, "Restic is a required test dependency"
    source = tmp_path / "live.sqlite"
    directory = tmp_path / "exports"
    with sqlite3.connect(source) as live:
        live.execute("PRAGMA journal_mode=WAL")
        live.execute("CREATE TABLE records (value INTEGER PRIMARY KEY)")
        live.commit()
        live.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        live.execute("INSERT INTO records VALUES (42)")
        live.commit()
        assert Path(str(source) + "-wal").stat().st_size > 0
        manifest = HELPER["export"]({
            "directory": str(directory),
            "sqlite": [{"name": "fixture", "path": str(source)}],
            "postgresql": [],
        })
    assert len(manifest["databases"]) == 1
    snapshot = next(directory.glob("generation-*")) / "fixture.sqlite"
    assert snapshot.stat().st_mode & 0o777 == PRIVATE_FILE_MODE
    assert directory.stat().st_mode & 0o777 == PRIVATE_DIRECTORY_MODE
    monkeypatch.setenv("RESTIC_REPOSITORY", str(tmp_path / "repository"))
    monkeypatch.setenv("RESTIC_PASSWORD", "disposable-fixture")
    monkeypatch.setenv("RESTIC_CACHE_DIR", str(tmp_path / "cache"))
    for arguments in [("init",), ("backup", str(directory))]:
        subprocess.run(
            [restic, *arguments], check=True, capture_output=True, shell=False
        )
    source.unlink()
    shutil.rmtree(directory)
    target = tmp_path / "restored"
    subprocess.run(
        [restic, "restore", f"latest:{directory}", "--target", str(target)],
        check=True,
        capture_output=True,
        shell=False,
    )
    restored = list(target.rglob("fixture.sqlite"))
    assert len(restored) == 1
    with sqlite3.connect(restored[0]) as database:
        assert database.execute("PRAGMA integrity_check").fetchall() == [("ok",)]
        assert database.execute("SELECT value FROM records").fetchall() == [(42,)]


def test_failed_export_preserves_complete_generation(tmp_path: Path) -> None:
    """A later required database failure cannot publish a partially new snapshot."""
    source = tmp_path / "live.sqlite"
    with sqlite3.connect(source) as live:
        live.execute("CREATE TABLE records (value INTEGER PRIMARY KEY)")
        live.execute("INSERT INTO records VALUES (7)")
    directory = tmp_path / "exports"
    entries = [{"name": "fixture", "path": str(source)}]
    policy = {"directory": str(directory), "sqlite": entries, "postgresql": []}
    HELPER["export"](policy)
    marker = (directory / "latest.json").read_bytes()
    complete = next(directory.glob("generation-*"))
    previous = (complete / "fixture.sqlite").read_bytes()
    with sqlite3.connect(source) as live:
        live.execute("INSERT INTO records VALUES (42)")
    entries.append({"name": "missing", "path": str(tmp_path / "missing.sqlite")})
    with pytest.raises(HELPER["ExportError"], match="Required database is absent"):
        HELPER["export"](policy)
    assert (directory / "latest.json").read_bytes() == marker
    assert (complete / "fixture.sqlite").read_bytes() == previous
    assert list(directory.glob("generation-*")) == [complete]
    assert list(directory.glob("pending-*")) == []
    assert (
        json.loads((complete / "manifest.json").read_text())["databases"][0]["name"]
        == "fixture"
    )
