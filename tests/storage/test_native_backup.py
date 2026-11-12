"""Exercise native writer quiescence and complete isolated backup restoration."""

from __future__ import annotations

import json
import runpy
import shutil
import subprocess
from pathlib import Path

import pytest

HELPER = runpy.run_path(
    str(
        Path(__file__).parents[2] / "hosts/nixos/desktop/local/storage/backup_helper.py"
    )
)


def policy(tmp_path: Path) -> dict:
    """Construct a disposable native writer policy.

    Returns:
        Private state paths and declared writer units.

    """
    return {
        "stateDirectory": str(tmp_path / "state"),
        "nativeGuardDirectory": str(tmp_path / "guards"),
        "coldUnits": ["writer.service", "dependency.service", "idle.timer"],
        "coldUnmounts": [],
        "bulkLock": str(tmp_path / "bulk.lock"),
    }


def control(monkeypatch: pytest.MonkeyPatch, states: dict[str, str]) -> list[list[str]]:
    """Replace systemd with observable independent unit states.

    Returns:
        The recorded control calls.

    """
    calls = []
    original = HELPER["run"]

    def run(arguments: list[str]) -> str:
        if arguments[0] != "systemctl":
            return original(arguments)
        calls.append(arguments)
        action = arguments[1]
        if action == "show":
            return (
                (states[arguments[2]] + "\n")
                if "--value" in arguments
                else "LoadState=loaded\nActiveState=" + states[arguments[2]] + "\n"
            )
        if action in {"stop", "start"}:
            for unit in arguments[2:]:
                states[unit] = "inactive" if action == "stop" else "active"
        return ""

    monkeypatch.setitem(HELPER["native_recover"].__globals__, "run", run)
    return calls


def test_native_failure_restores_initial_writers_and_preserves_inactive_units(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Export failure resumes original writers without starting an idle timer."""
    cfg = policy(tmp_path)
    states = {
        "writer.service": "active",
        "dependency.service": "active",
        "idle.timer": "inactive",
    }
    calls = control(monkeypatch, states)

    def fail_export() -> None:
        message = "failed export"
        raise ValueError(message)

    with (  # ruff: ignore[pytest-raises-with-multiple-statements] - Exercise recovery after an export-body failure.
        pytest.raises(ValueError, match="failed export"),
        HELPER["native_quiesce"](cfg),
    ):
        assert set(states.values()) == {"inactive"}
        assert len(list((tmp_path / "guards").glob("*.d/*.conf"))) == len(states)
        fail_export()
    assert states == {
        "writer.service": "active",
        "dependency.service": "active",
        "idle.timer": "inactive",
    }
    assert ["systemctl", "start", "idle.timer"] not in calls
    assert not list((tmp_path / "guards").glob("*.d/*.conf"))
    assert not (tmp_path / "state/native-operation.json").exists()


def test_native_cleanup_attempts_every_restart_and_retains_recovery_journal(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A failed dependency restart must not prevent the remaining restart attempts."""
    cfg = policy(tmp_path)
    states = {
        "writer.service": "active",
        "dependency.service": "active",
        "idle.timer": "inactive",
    }
    calls = control(monkeypatch, states)
    run = HELPER["run"].__globals__["run"]

    def fail(arguments: list[str]) -> str:
        if arguments == ["systemctl", "start", "dependency.service"]:
            raise subprocess.CalledProcessError(1, arguments)
        return run(arguments)

    monkeypatch.setitem(HELPER["native_recover"].__globals__, "run", fail)
    with (
        pytest.raises(HELPER["BackupError"], match="restart"),
        HELPER["native_quiesce"](cfg),
    ):
        pass
    assert ["systemctl", "start", "writer.service"] in calls
    assert (tmp_path / "state/native-operation.json").exists()


def test_native_guard_conflict_refuses_before_stopping_any_writer(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """An operator guard must remain untouched and prevent writer shutdown."""
    cfg = policy(tmp_path)
    path = tmp_path / "guards/writer.service.d/90-desktop-native-backup.conf"
    path.parent.mkdir(parents=True)
    path.write_text("operator guard\n", encoding="utf-8")
    calls = control(
        monkeypatch,
        {
            "writer.service": "active",
            "dependency.service": "active",
            "idle.timer": "inactive",
        },
    )
    with pytest.raises(HELPER["BackupError"]), HELPER["native_quiesce"](cfg):
        pytest.fail("Guard conflict admitted backup")
    assert not any(call[1] == "stop" for call in calls)
    assert path.read_text(encoding="utf-8") == "operator guard\n"


@pytest.mark.parametrize("configured_scratch", [False, True])
def test_native_restic_roundtrip_checks_real_application_files(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, configured_scratch: bool
) -> None:
    """Restore actual Restic data with file, ownership and symlink verification."""
    restic = shutil.which("restic")
    assert restic is not None
    cfg = policy(tmp_path)
    data = tmp_path / "application"
    data.mkdir()
    (data / "database").write_bytes(b"committed application data\x00")
    (data / "upload").symlink_to("database")
    cfg.update(
        coldPaths=[str(data)],
        coldRestic=restic,
        coldPrepareCommand=[],
        destinations={"remote": {}},
    )
    monkeypatch.setenv("RESTIC_REPOSITORY", str(tmp_path / "repository"))
    monkeypatch.setenv("RESTIC_PASSWORD", "public-disposable-test-password")
    monkeypatch.setenv("RESTIC_CACHE_DIR", str(tmp_path / "cache"))
    monkeypatch.setenv("CACHE_DIRECTORY", str(tmp_path / "restore"))
    (tmp_path / "restore").mkdir()
    subprocess.run([restic, "init"], check=True, capture_output=True)
    calls = control(
        monkeypatch,
        {
            "writer.service": "active",
            "dependency.service": "active",
            "idle.timer": "inactive",
        },
    )
    monkeypatch.setitem(HELPER["cold_backup"].__globals__, "guard", lambda _: None)
    scratch = tmp_path / ("data-volume-scratch" if configured_scratch else "restore")
    scratch.mkdir(exist_ok=True)
    if configured_scratch:
        cfg["coldRestoreScratch"] = str(scratch)
    original_run = HELPER["run"]
    restore_targets: list[Path] = []

    def record_run(arguments: list[str]) -> str:
        if "restore" in arguments and "--target" in arguments:
            restore_targets.append(Path(arguments[arguments.index("--target") + 1]))
        return original_run(arguments)

    monkeypatch.setitem(HELPER["cold_backup"].__globals__, "run", record_run)
    HELPER["cold_backup"](cfg, "remote")
    assert restore_targets
    assert all(target.is_relative_to(scratch) for target in restore_targets)
    assert HELPER["read_stamp"](cfg, "remote", "cold-backup") > 0
    assert HELPER["read_stamp"](cfg, "remote", "cold-restore") > 0
    assert ["systemctl", "start", "writer.service"] in calls
    receipt = json.loads(
        (tmp_path / "state/checks/remote-native-restore.json").read_text(
            encoding="utf-8"
        )
    )
    assert receipt["filesVerified"] == len(list(data.iterdir()))
    assert not list((tmp_path / "restore").iterdir())


def test_manifest_detects_same_size_corruption(tmp_path: Path) -> None:
    """Equal file sizes must not hide changed data."""
    data = tmp_path / "data"
    data.write_bytes(b"good")
    original = HELPER["file_manifest"]([str(data)])
    data.write_bytes(b"evil")
    assert HELPER["file_manifest"]([str(data)]) != original


def test_partial_stop_failure_still_restores_every_original_writer(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A failed stop transaction may already have stopped dependent services."""
    cfg = policy(tmp_path)
    states = {
        "writer.service": "active",
        "dependency.service": "active",
        "idle.timer": "inactive",
    }
    calls = control(monkeypatch, states)
    delegate = HELPER["run"].__globals__["run"]

    def run(arguments: list[str]) -> str:
        if arguments[1] == "stop":
            states["writer.service"] = "inactive"
            states["dependency.service"] = "inactive"
            raise subprocess.CalledProcessError(1, arguments)
        return delegate(arguments)

    monkeypatch.setitem(HELPER["native_recover"].__globals__, "run", run)
    with pytest.raises(subprocess.CalledProcessError), HELPER["native_quiesce"](cfg):
        pytest.fail("A failed stop must refuse capture")
    assert states["writer.service"] == "active"
    assert states["dependency.service"] == "active"
    assert ["systemctl", "start", "idle.timer"] not in calls
