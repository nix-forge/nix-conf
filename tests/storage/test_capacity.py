"""Exercise real capacity decisions without filling or pruning a live filesystem."""

from __future__ import annotations

import json
import runpy
from pathlib import Path
from types import SimpleNamespace
from typing import TYPE_CHECKING

import pytest

if TYPE_CHECKING:
    from typing import Any

HELPER = runpy.run_path(
    str(Path(__file__).parents[2] / "hosts/nixos/desktop/local/storage/capacity.py")
)
COMBINED_REQUEST = 70
RECOVERED_SPACE = 260
FAILED_EXIT = 75


def test_cache_refuses_missing_data_without_creating_fallback(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Manual backup cache admission never creates a root fallback directory."""
    root = tmp_path / "absent-cache"
    monkeypatch.setitem(
        HELPER["cache_guard"].__globals__,
        "mounted",
        lambda _: (_ for _ in ()).throw(ValueError("unmounted")),
    )
    with pytest.raises(ValueError, match="unmounted"):
        HELPER["cache_guard"]({"cache": {"mount": "/srv/data", "root": str(root)}})
    assert not root.exists()


def test_cache_requires_owned_subvolume_and_confined_paths(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A prepared subvolume accepts its cache and refuses redirection outside it."""
    root = tmp_path / "cache"
    temporary = root / "tmp"
    temporary.mkdir(parents=True)
    monkeypatch.setitem(
        HELPER["cache_guard"].__globals__, "mounted", lambda _: sample(100)
    )
    original_stat = Path.stat
    monkeypatch.setattr(
        Path,
        "stat",
        lambda self, *a, **kw: (
            SimpleNamespace(st_ino=256, st_uid=0, st_mode=0o40700)
            if self == root
            else original_stat(self, *a, **kw)
        ),
    )
    cfg = {"cache": {"mount": "/srv/data", "root": str(root)}}
    monkeypatch.setenv("TMPDIR", str(temporary))
    monkeypatch.setenv("RESTIC_CACHE_DIR", str(root / "repository"))
    assert HELPER["cache_guard"](cfg) == {"ready": True}
    monkeypatch.setenv("RESTIC_CACHE_DIR", str(tmp_path / "fallback"))
    with pytest.raises(ValueError, match="outside"):
        HELPER["cache_guard"](cfg)


def policy(tmp_path: Path) -> dict[str, Any]:
    """Use small independent thresholds so boundary decisions remain explicit.

    Returns:
        A private disposable capacity policy.

    """
    return {
        "stateDirectory": str(tmp_path),
        "bulkLock": str(tmp_path / "bulk.lock"),
        "collectBelowBytes": 200,
        "collectTargetBytes": 250,
        "retrySeconds": 3600,
        "retryDropBytes": 10,
        "collectorStaleSeconds": 3600,
        "nixStore": "/nonexistent",
        "filesystems": [
            {
                "path": "/",
                "requireMount": True,
                "warningBytes": 150,
                "warningRecoveryBytes": 175,
                "criticalBytes": 75,
                "criticalRecoveryBytes": 100,
                "admissionBytes": 150,
            }
        ],
    }


def sample(available: int, identity: str = "root") -> dict[str, Any]:
    """Represent Btrfs mount aliases with the same filesystem UUID.

    Returns:
        A synthetic mount sample.

    """
    return {"identity": identity, "mount": "/", "available": available}


@pytest.mark.parametrize(
    ("available", "previous", "expected"),
    [
        (74, "healthy", "critical"),
        (99, "critical", "critical"),
        (100, "critical", "warning"),
        (150, "healthy", "healthy"),
        (174, "warning", "warning"),
        (175, "warning", "healthy"),
    ],
)
def test_alert_hysteresis(
    available: int, previous: str, expected: str, tmp_path: Path
) -> None:
    """Do not oscillate at a single warning or critical threshold."""
    assert (
        HELPER["severity"](available, policy(tmp_path)["filesystems"][0], previous)
        == expected
    )


def test_subvolume_requests_share_one_budget(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Two aliases cannot each spend the same available bytes independently."""
    namespace = HELPER["admission"].__globals__
    monkeypatch.setitem(namespace, "probe", lambda _: sample(210))
    result = HELPER["admission"](policy(tmp_path), [(str(tmp_path), 40), ("/", 30)])
    assert not result["admitted"]
    assert result["filesystems"][0]["additionalBytes"] == COMBINED_REQUEST


def test_admission_boundary_and_unknown_filesystem(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A declared peak must leave the whole floor; an unconfigured disk refuses."""
    namespace = HELPER["admission"].__globals__
    monkeypatch.setitem(namespace, "probe", lambda _: sample(200))
    assert HELPER["admission"](policy(tmp_path), [("/", 50)])["admitted"]
    assert not HELPER["admission"](policy(tmp_path), [("/", 51)])["admitted"]
    monkeypatch.setitem(
        namespace, "probe", lambda path: sample(200, "root" if path == "/" else "other")
    )
    with pytest.raises(ValueError, match="no capacity policy"):
        HELPER["admission"](policy(tmp_path), [(str(tmp_path), 1)])


def test_absent_data_mount_never_falls_back_to_root(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A missing optional disk must not turn an intended data write into root data."""
    namespace = HELPER["admission"].__globals__
    monkeypatch.setitem(namespace, "probe", lambda _: sample(999))
    cfg = policy(tmp_path)
    cfg["filesystems"].append(
        cfg["filesystems"][0] | {"path": str(tmp_path), "aliases": []}
    )
    with pytest.raises(ValueError, match="mount is unavailable"):
        HELPER["admission"](cfg, [(str(tmp_path), 1)])
    assert HELPER["admission"](cfg, [("/", 1)])["admitted"]


def test_collector_rechecks_after_lock(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Space recovered while queued means no extra GC request is needed."""
    cfg = policy(tmp_path)
    Path(cfg["bulkLock"]).touch()
    namespace = HELPER["collect"].__globals__
    samples = iter([sample(190), sample(260), sample(260)])
    monkeypatch.setitem(namespace, "mounted", lambda _: next(samples))
    result = HELPER["collect"](cfg)
    assert result["status"] == "skipped"
    assert result["afterBytes"] == RECOVERED_SPACE


def test_collector_records_no_progress_and_backs_off(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Live roots must produce evidence instead of an unbounded repeated scan."""
    cfg = policy(tmp_path)
    Path(cfg["bulkLock"]).touch()
    fake = tmp_path / "fake-nix-store"
    fake.write_text('#!/bin/sh\nprintf \'%s\\n\' "$@" > "$0.args"\n')
    fake.chmod(0o700)
    cfg["nixStore"] = str(fake)
    monkeypatch.setitem(HELPER["collect"].__globals__, "mounted", lambda _: sample(190))
    first = HELPER["collect"](cfg)
    assert first["status"] == "unreclaimable"
    assert fake.with_suffix(".args").read_text().splitlines() == [
        "--store",
        "daemon",
        "--gc",
        "--max-freed",
        "60",
    ]
    assert HELPER["collect"](cfg) == first
    assert json.loads((tmp_path / "collection.json").read_text()) == first


def test_collector_failure_is_not_success(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A failed request remains failed even if another writer frees space."""
    cfg = policy(tmp_path)
    Path(cfg["bulkLock"]).touch()
    fake = tmp_path / "fake-nix-store"
    fake.write_text("#!/bin/sh\nexit 75\n")
    fake.chmod(0o700)
    cfg["nixStore"] = str(fake)
    monkeypatch.setitem(HELPER["collect"].__globals__, "mounted", lambda _: sample(190))
    result = HELPER["collect"](cfg)
    assert result["status"] == "failed"
    assert result["exitCode"] == FAILED_EXIT


def test_status_retains_hysteresis_and_reports_missing_collector(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Absent collector receipts and a partially recovered warning stay visible."""
    cfg = policy(tmp_path)
    monkeypatch.setitem(HELPER["status"].__globals__, "mounted", lambda _: sample(140))
    first = HELPER["status"](cfg)
    assert first["filesystems"]["/"]["severity"] == "warning"
    assert any("missing or stale" in text for text in first["messages"])
    monkeypatch.setitem(HELPER["status"].__globals__, "mounted", lambda _: sample(160))
    assert HELPER["status"](cfg)["filesystems"]["/"]["severity"] == "warning"


def test_collection_log_is_bounded_without_truncating_the_child_stream(
    tmp_path: Path,
) -> None:
    """Large GC output cannot consume an unbounded root log or parent heap."""
    import sys  # ruff: ignore[import-outside-top-level] - Match the running test interpreter.

    fixture = tmp_path / "output.py"
    fixture.write_text(
        "import sys\nsys.stdout.buffer.write(b'x' * 200000 + b'last-error')\n",
        encoding="utf-8",
    )
    log = tmp_path / "collection.log"
    assert HELPER["run_collection"]([sys.executable, str(fixture)], log) == 0
    content = log.read_bytes()
    assert len(content) == HELPER["MAX_COLLECTION_LOG_BYTES"]
    assert content.endswith(b"last-error")


def test_busy_execution_reservation_defers_collection_without_waiting(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """An idle controller never steals a running job's lock or restarts its work."""
    import fcntl  # ruff: ignore[import-outside-top-level] - Linux/POSIX lock fixture.

    cfg = policy(tmp_path)
    Path(cfg["bulkLock"]).touch()
    monkeypatch.setitem(HELPER["collect"].__globals__, "mounted", lambda _: sample(190))
    with Path(cfg["bulkLock"]).open("r+", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        result = HELPER["collect"](cfg)
    assert result["status"] == "deferred"
    assert not (tmp_path / "collection.log").exists()


def test_low_memory_defers_idle_collection_without_bypassing_daemon_budget(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """The collector respects host headroom even after the bulk lock becomes free."""
    cfg = policy(tmp_path)
    cfg["minimumMemoryAvailableBytes"] = 2**60
    Path(cfg["bulkLock"]).touch()
    monkeypatch.setitem(HELPER["collect"].__globals__, "mounted", lambda _: sample(190))
    assert HELPER["collect"](cfg)["status"] == "deferred-memory"


def test_unmounted_automount_is_not_accessed_by_unrelated_admission(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Reading optional mount metadata must not unlock or touch the missing disk."""
    from types import SimpleNamespace  # ruff: ignore[import-outside-top-level] - Isolate the subprocess adapter.

    namespace = HELPER["probe"].__globals__
    monkeypatch.setattr(namespace["shutil"], "which", lambda _: "/fixture/findmnt")
    monkeypatch.setitem(
        namespace,
        "subprocess",
        SimpleNamespace(
            run=lambda *_, **__: SimpleNamespace(
                stdout=json.dumps({
                    "filesystems": [
                        {"uuid": None, "target": str(tmp_path), "fstype": "autofs"}
                    ]
                })
            )
        ),
    )
    monkeypatch.setattr(
        namespace["os"],
        "statvfs",
        lambda _: pytest.fail("An absent automount was accessed"),
    )
    with pytest.raises(ValueError, match="unmounted automount"):
        HELPER["probe"](str(tmp_path))


def test_snapshot_creation_stops_at_critical_pressure_but_recovery_still_runs(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Do not create new snapshots under critical pressure or block cleanup itself."""
    cfg = policy(tmp_path)
    monkeypatch.setitem(HELPER["admission"].__globals__, "probe", lambda _: sample(74))
    assert not HELPER["admission"](cfg, [("/", 0)], snapshot=True)["admitted"]
    assert HELPER["admission"](cfg, [("/", 0)], recovery=True)["admitted"]


def test_mounted_filesystem_above_autofs_is_observed_without_mounting(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The static mount table distinguishes a live stacked volume from idle autofs."""
    namespace = HELPER["probe"].__globals__
    calls = []
    statistics = []

    def run(arguments: list[str], **_: object) -> object:
        calls.append(arguments)
        layers = [{"uuid": None, "target": "/mnt/optional", "fstype": "autofs"}]
        if "--mountpoint" in arguments:
            layers.append({
                "uuid": "mounted-data",
                "target": "/mnt/optional",
                "fstype": "btrfs",
            })
        return SimpleNamespace(stdout=json.dumps({"filesystems": layers}))

    def usage(path: str) -> object:
        statistics.append(path)
        return SimpleNamespace(f_bavail=80, f_frsize=1)

    monkeypatch.setitem(namespace, "subprocess", SimpleNamespace(run=run))
    monkeypatch.setattr(namespace["shutil"], "which", lambda _: "/fixture/findmnt")
    monkeypatch.setattr(namespace["os"], "statvfs", usage)
    result = HELPER["probe"]("/mnt/optional/child")
    assert result == {
        "identity": "mounted-data",
        "mount": "/mnt/optional",
        "available": 80,
    }
    assert ["--mountpoint" in arguments for arguments in calls] == [False, True]
    assert statistics == ["/mnt/optional/child"]
