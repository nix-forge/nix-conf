"""Check scrub admission against real swap headroom and independent recovery."""

import json
import os
import runpy
import subprocess
import sys
from pathlib import Path

import pytest

HELPER = runpy.run_path(
    str(Path(__file__).parents[2] / "hosts/nixos/desktop/local/storage/root_scrub.py")
)
GIB = 1024**3


def test_zram_does_not_replace_disk_swap_reserve() -> None:
    """Compressed RAM cannot substitute for independent swap capacity."""
    entries = [
        {"name": "/swap/file", "kind": "file", "size": 8 * GIB, "used": GIB},
        {"name": "/dev/zram0", "kind": "partition", "size": 30 * GIB, "used": 0},
        {"name": "/dev/disk", "kind": "partition", "size": 16 * GIB, "used": 9 * GIB},
    ]
    with pytest.raises(HELPER["ScrubError"], match="disk swap free"):
        HELPER["capacity"](entries, 12 * GIB, "/swap/file")
    entries[-1]["used"] = 7 * GIB
    HELPER["capacity"](entries, 12 * GIB, "/swap/file")


def test_swapfile_drain_needs_extra_ram_and_rejects_other_files() -> None:
    """Admission must account for drained pages and every active swapfile."""
    entries = [
        {"name": "/swap/file", "kind": "file", "size": 8 * GIB, "used": 3 * GIB},
        {"name": "/dev/disk", "kind": "partition", "size": 16 * GIB, "used": 0},
    ]
    with pytest.raises(HELPER["ScrubError"], match="six GiB"):
        HELPER["capacity"](entries, 8 * GIB, "/swap/file")
    entries[0]["name"] = "/swap/unknown"
    with pytest.raises(HELPER["ScrubError"], match="Additional active"):
        HELPER["capacity"](entries, 20 * GIB, "/swap/file")


def test_recovery_resumes_only_originally_active_swap(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Independent cleanup preserves the swapfile activation state."""
    cfg = {
        "stateDirectory": str(tmp_path),
        "swapUnit": "swap-file.swap",
        "swapfile": "/swap/file",
    }
    guard = tmp_path / "guard"
    guard.write_text("owned", encoding="utf-8")
    journal = tmp_path / "root-scrub-operation.json"
    journal.write_text(
        json.dumps({"active": True, "guard": str(guard), "body": "owned"}),
        encoding="utf-8",
    )
    calls = []
    monkeypatch.setitem(HELPER["recover"].__globals__, "run", calls.append)
    monkeypatch.setitem(
        HELPER["recover"].__globals__, "swaps", lambda: [{"name": "/swap/file"}]
    )
    HELPER["recover"](cfg)
    assert calls == [
        ["systemctl", "daemon-reload"],
        ["systemctl", "start", "swap-file.swap"],
    ]
    assert not journal.exists()
    assert not guard.exists()
    calls.clear()
    journal.write_text(
        json.dumps({"active": False, "guard": str(guard), "body": "owned"}),
        encoding="utf-8",
    )
    HELPER["recover"](cfg)
    assert calls == [["systemctl", "daemon-reload"]]


def test_recovery_does_not_destroy_changed_operator_guard(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A changed guard must survive recovery for operator inspection."""
    guard = tmp_path / "guard"
    guard.write_text("operator", encoding="utf-8")
    journal = tmp_path / "root-scrub-operation.json"
    journal.write_text(
        json.dumps({"active": True, "guard": str(guard), "body": "owned"}),
        encoding="utf-8",
    )
    monkeypatch.setitem(
        HELPER["recover"].__globals__,
        "run",
        lambda _: pytest.fail("Must not change operator state"),
    )
    with pytest.raises(HELPER["ScrubError"], match="guard changed"):
        HELPER["recover"]({"stateDirectory": str(tmp_path)})
    assert guard.read_text(encoding="utf-8") == "operator"
    assert journal.exists()


def test_recovery_resumes_swap_when_owned_scrub_is_already_idle(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Btrfs cancel exit two means idle and must not block swap restoration."""
    guard = tmp_path / "guard"
    guard.write_text("owned", encoding="utf-8")
    journal = tmp_path / "root-scrub-operation.json"
    journal.write_text(
        json.dumps({
            "active": True,
            "started": True,
            "guard": str(guard),
            "body": "owned",
        }),
        encoding="utf-8",
    )
    calls = []
    namespace = HELPER["recover"].__globals__
    monkeypatch.setitem(namespace, "run", calls.append)
    monkeypatch.setitem(namespace, "btrfs_executable", lambda: "/test/btrfs")
    monkeypatch.setitem(namespace, "swaps", lambda: [{"name": "/swap/file"}])
    monkeypatch.setattr(
        subprocess, "run", lambda *a, **_kwargs: subprocess.CompletedProcess(a, 2)
    )
    HELPER["recover"]({
        "stateDirectory": str(tmp_path),
        "swapUnit": "file.swap",
        "swapfile": "/swap/file",
    })
    assert ["systemctl", "start", "file.swap"] in calls
    assert not journal.exists()


def test_failed_atomic_journal_update_preserves_recovery_state(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """An interrupted publication must leave the preceding valid journal intact."""
    journal = tmp_path / "operation.json"
    original = {"active": True, "started": True}
    journal.write_text(json.dumps(original), encoding="utf-8")

    def fail(_source: Path, _target: Path) -> None:
        message = "publication interrupted"
        raise OSError(message)

    monkeypatch.setattr(Path, "replace", fail)
    with pytest.raises(OSError, match="publication interrupted"):
        HELPER["save_operation"](journal, {"active": True, "started": False})
    assert json.loads(journal.read_text(encoding="utf-8")) == original


@pytest.mark.skipif(not hasattr(os, "pidfd_open"), reason="Linux pidfd supervisor")
def test_scrub_supervisor_uses_supported_limit_and_publishes_idle_state(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Exercise a real child and pidfd exit with the documented scrub options."""
    fixture = Path(__file__).with_name("fixtures") / "scrub_success.py"
    command = tmp_path / "scrub.py"
    command.write_text(
        "#!" + sys.executable + "\n" + fixture.read_text(encoding="utf-8"),
        encoding="utf-8",
    )
    command.chmod(0o700)
    journal = tmp_path / "operation.json"
    journal.write_text(json.dumps({"active": True}), encoding="utf-8")
    namespace = HELPER["run_scrub"].__globals__
    monkeypatch.setitem(namespace, "btrfs_executable", lambda: str(command))
    monkeypatch.setitem(namespace, "swaps", list)
    HELPER["run_scrub"]({"swapfile": "/swap/file"}, journal)
    assert json.loads(command.with_suffix(".json").read_text(encoding="utf-8")) == [
        "scrub",
        "start",
        "-B",
        "--limit",
        "800M",
        "/",
    ]
    assert json.loads(journal.read_text(encoding="utf-8"))["started"] is False
