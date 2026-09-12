"""Exercise recovery claims and real Restic round trips using disposable data."""

from __future__ import annotations

import json
import runpy
import shutil
import subprocess
from pathlib import Path
from typing import TYPE_CHECKING

import pytest

if TYPE_CHECKING:
    from typing import Any

HELPER = runpy.run_path(
    str(
        Path(__file__).parents[2] / "hosts/nixos/desktop/local/storage/backup-helper.py"
    )
)


def destination() -> dict[str, Any]:
    """Return an illustrative destination policy.

    Returns:
        Non-secret topology and scheduling metadata.

    """
    return {
        "medium": "hdd",
        "offsite": True,
        "protection": "offline",
        "failureDomain": "rotated-media",
        "maxAgeHours": 48,
        "maxVerificationAgeDays": 14,
    }


def test_empty_policy_is_not_protected(tmp_path: Path) -> None:
    """An unprovisioned backup configuration must report its missing copies."""
    result = HELPER["status"]({"stateDirectory": str(tmp_path), "destinations": {}})
    assert any("Two independent" in item for item in result)
    assert any("offline" in item for item in result)


def test_two_repositories_on_one_domain_are_not_independent() -> None:
    """Counting repositories cannot conceal a shared failure domain."""
    result = HELPER["policy_gaps"]({"first": destination(), "second": destination()})
    assert any("failure domains" in item for item in result)


def test_backup_success_does_not_certify_recovery(tmp_path: Path) -> None:
    """Integrity, sample restore and application drills need their own receipts."""
    policy = {
        "stateDirectory": str(tmp_path),
        "destinations": {"remote": destination()},
    }
    HELPER["stamp"](policy, "remote", "backup")
    result = HELPER["status"](policy)
    assert "remote: backup is missing or overdue" not in result
    for phase in ("integrity", "restore", "recovery-drill"):
        assert f"remote: {phase} is missing or overdue" in result


def test_failure_remains_visible_after_recent_success(tmp_path: Path) -> None:
    """A failed new attempt must override fresh successful receipts until retry succeeds."""
    policy = {
        "stateDirectory": str(tmp_path),
        "destinations": {"remote": destination()},
    }
    HELPER["stamp"](policy, "remote", "backup")
    HELPER["finish"](policy, "remote", "backup", "success")
    previous = HELPER["read_stamp"](policy, "remote", "backup")
    HELPER["finish"](policy, "remote", "backup", "exit-code")
    assert HELPER["read_stamp"](policy, "remote", "backup") == previous
    assert "remote: latest backup attempt failed" in HELPER["status"](policy)
    HELPER["finish"](policy, "remote", "backup", "success")
    assert "remote: latest backup attempt failed" not in HELPER["status"](policy)


def test_normal_backup_does_not_certify_application_coverage(tmp_path: Path) -> None:
    """Durable application state needs independent cold backup and restore evidence."""
    policy = {
        "stateDirectory": str(tmp_path),
        "destinations": {"remote": destination()},
    }
    for phase in ("backup", "integrity", "restore", "recovery-drill"):
        HELPER["stamp"](policy, "remote", phase)
    result = HELPER["status"](policy)
    assert "remote: cold-backup is missing or overdue" in result
    assert "remote: cold-restore is missing or overdue" in result


@pytest.mark.parametrize(
    "running",
    [
        "user@1000.service active",
        "multi-user.target active",
        "qemu-system-x86",
        "containerd-shim",
    ],
)
def test_cold_backup_rejects_active_writers(
    monkeypatch: pytest.MonkeyPatch, running: str
) -> None:
    """Rescue mode alone is insufficient when a user manager or workload survived."""

    def fake_run(arguments: list[str]) -> str:
        if arguments[:2] == ["systemctl", "list-units"]:
            return running if "." in running else ""
        if arguments[0] == "ps":
            return running if "." not in running else ""
        return ""

    monkeypatch.setitem(HELPER["cold_guard"].__globals__, "run", fake_run)
    with pytest.raises(HELPER["BackupError"]):
        HELPER["cold_guard"]()


def test_stale_or_corrupt_receipt_does_not_pass(tmp_path: Path) -> None:
    """Future dates and malformed receipts must not turn monitoring green."""
    policy = {
        "stateDirectory": str(tmp_path),
        "destinations": {"remote": destination()},
    }
    HELPER["stamp"](policy, "remote", "integrity")
    path = HELPER["state_file"](policy, "remote", "integrity")
    path.write_text(json.dumps({"completed": 99999999999}), encoding="utf-8")
    assert HELPER["read_stamp"](policy, "remote", "integrity") == 0
    path.write_text("broken", encoding="utf-8")
    assert HELPER["read_stamp"](policy, "remote", "integrity") == 0


def test_public_credentials_are_rejected(tmp_path: Path) -> None:
    """Credential preflight refuses a world-readable file."""
    path = tmp_path / "credential"
    path.write_text("disposable fixture", encoding="utf-8")
    path.chmod(0o644)
    with pytest.raises(HELPER["BackupError"]):
        HELPER["private_file"](str(path))


def test_real_backup_and_verified_restore(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Restore actual Restic data, then reject a deliberately mismatched canary."""
    policy = {"stateDirectory": str(tmp_path / "state"), "destinations": {}}
    canary = HELPER["canary"](policy)
    original = canary.read_bytes()
    assert HELPER["canary"](policy).read_bytes() == original
    repository = tmp_path / "repository"
    monkeypatch.setenv("RESTIC_REPOSITORY", str(repository))
    monkeypatch.setenv("RESTIC_PASSWORD", "public-test-fixture-not-a-real-password")
    monkeypatch.setenv("RESTIC_CACHE_DIR", str(tmp_path / "cache"))
    monkeypatch.setenv("CACHE_DIRECTORY", str(tmp_path))
    for arguments in (
        ["restic", "init"],
        ["restic", "backup", "--tag", "desktop-files", str(canary)],
        ["restic", "check", "--read-data"],
    ):
        subprocess.run(
            arguments, check=True, capture_output=True, text=True, shell=False
        )
    HELPER["restore"](policy, "remote")
    assert not list(tmp_path.glob("desktop-restore-*"))

    # Exercise the separate durable-data snapshot, after isolated tests have
    # checked its rescue/process guard. Do not enter rescue mode in this test.
    application = tmp_path / "application"
    application.mkdir()
    durable = application / "database-export"
    durable.write_text("durable application fixture", encoding="utf-8")
    policy["coldPaths"] = [str(application), str(tmp_path / "absent-application")]
    policy["destinations"] = {"remote": destination()}
    monkeypatch.setitem(HELPER["cold_backup"].__globals__, "guard", lambda _: None)
    monkeypatch.setitem(HELPER["cold_backup"].__globals__, "cold_guard", lambda: None)
    HELPER["cold_backup"](policy, "remote")
    restic = shutil.which("restic")
    assert restic is not None
    restored_data = subprocess.run(
        [restic, "dump", "--tag", "desktop-cold", "latest", str(durable)],
        check=True,
        capture_output=True,
        text=True,
        shell=False,
    )
    assert restored_data.stdout == durable.read_text(encoding="utf-8")
    assert HELPER["read_stamp"](policy, "remote", "cold-backup") > 0
    assert HELPER["read_stamp"](policy, "remote", "cold-restore") > 0

    canary.write_text("deliberately changed", encoding="utf-8")
    with pytest.raises(HELPER["BackupError"]):
        HELPER["restore"](policy, "remote")
    assert not list(tmp_path.glob("desktop-restore-*"))


@pytest.mark.parametrize(
    "repository",
    [
        "/var/lib/backups/restic",
        "var/lib/backups/restic",
        "local:/var/lib/backups/restic",
        "local:relative-repository",
        "../backup:archive",
        r"\backup",
        r"..\backup:archive",
        "C:/backup",
    ],
)
def test_local_repositories_require_external_mount(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, repository: str
) -> None:
    """All Restic local path forms need the same external-media protection."""
    repository_file = tmp_path / "repository"
    repository_file.write_text(repository, encoding="utf-8")
    monkeypatch.setitem(HELPER["guard"].__globals__, "private_file", Path)
    with pytest.raises(HELPER["BackupError"], match="explicit external mount"):
        HELPER["guard"]({"repositoryFile": str(repository_file), "requiredMounts": []})


@pytest.mark.parametrize("device", ["8:1", "8:2"])
def test_explicit_local_backend_checks_source_device(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, device: str
) -> None:
    """A declared external mount must also be on a separate filesystem."""
    repository_file = tmp_path / "repository"
    repository_file.write_text(f"local:{tmp_path}/backup", encoding="utf-8")
    monkeypatch.setitem(HELPER["guard"].__globals__, "private_file", Path)

    def fake_run(arguments: list[str]) -> str:
        if arguments[0] == "mountpoint":
            return ""
        return "8:1" if arguments[-1] in {"/", "/srv/data"} else device

    monkeypatch.setitem(HELPER["guard"].__globals__, "run", fake_run)
    policy = {
        "repositoryFile": str(repository_file),
        "requiredMounts": [str(tmp_path)],
    }
    if device == "8:1":
        with pytest.raises(HELPER["BackupError"], match="source filesystem"):
            HELPER["guard"](policy)
    else:
        HELPER["guard"](policy)
