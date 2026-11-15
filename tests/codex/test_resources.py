"""Exercise launch ordering, pressure debounce and isolated task ownership."""

from __future__ import annotations

# ruff: file-ignore[suspicious-subprocess-import, subprocess-without-shell-equals-true, magic-value-comparison] -- Subprocess fixtures and literal expected statuses exercise the command contract.
import contextlib
import json
import os
import random
import runpy
import shutil
import sqlite3
import subprocess
import sys
import zlib
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "homes/desktop/local/codex-resources/scripts"
FIXTURES = Path(__file__).with_name("fixtures")
PRESSURE = runpy.run_path(str(SCRIPTS / "codex_pressure.py"))


def executable(directory: Path, name: str, fixture: str) -> Path:
    """Install a native command fixture with the test interpreter.

    Returns:
        Executable fixture path.

    """
    path = directory / name
    path.write_text("#!" + sys.executable + "\n" + (FIXTURES / fixture).read_text())
    path.chmod(0o700)
    return path


@pytest.mark.skipif(
    sys.platform != "linux", reason="Linux desktop launch uses pipe2 and systemd"
)
@pytest.mark.parametrize("reload_fails", [False, True])
def test_launcher_gates_exec_and_removes_owned_policy(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, reload_fails: bool
) -> None:
    """The application sees policy before startup, or cannot start at all."""
    executable(tmp_path, "systemctl", "resource_systemctl.py")
    monkeypatch.delenv("RUNTIME_DIRECTORY", raising=False)
    monkeypatch.delenv("CODEX_LAUNCH_UNIT", raising=False)
    events = tmp_path / "events"
    monkeypatch.setenv("PATH", str(tmp_path) + os.pathsep + os.environ["PATH"])
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path))
    monkeypatch.setenv("CODEX_TEST_EVENTS", str(events))
    if reload_fails:
        monkeypatch.setenv("CODEX_TEST_RELOAD_FAIL", "1")
    else:
        monkeypatch.delenv("CODEX_TEST_RELOAD_FAIL", raising=False)
    result = subprocess.run(
        [
            sys.executable,
            str(SCRIPTS / "codex_launch.py"),
            sys.executable,
            str(FIXTURES / "resource_app.py"),
            "codex://fixture?a=$value",
            "two words",
        ],
        check=False,
        shell=False,
        capture_output=True,
        text=True,
    )
    lines = events.read_text().splitlines()
    assert lines[0] == "reload"
    assert not list(tmp_path.glob("systemd/user/*/90-codex-slice.conf"))
    if reload_fails:
        assert result.returncode != 0
        assert all(line == "reload" for line in lines)
    else:
        assert result.returncode == 7
        observed = json.loads(lines[1])
        assert "Slice=app-codex.slice" in observed["policy"]
        assert observed["args"] == ["codex://fixture?a=$value", "two words"]
        assert lines[-1] == "reload"


def pressure_config(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> dict:
    """Create real kernel-shaped accounting files and a notification sink.

    Returns:
        Monitor configuration backed by disposable files.

    """
    executable(tmp_path, "notify", "resource_notify.py")
    monkeypatch.setenv("CODEX_TEST_NOTIFICATIONS", str(tmp_path / "notices"))
    group = tmp_path / "cgroup"
    group.mkdir()
    (group / "memory.current").write_text("100\n")
    (group / "memory.swap.current").write_text("990\n")
    psi = "some avg10=0.00 avg60=0.00 avg300=0.00 total=0\nfull avg10=0.00 avg60=0.00 avg300=0.00 total=0\n"
    (group / "memory.pressure").write_text(psi)
    (tmp_path / "system.pressure").write_text(psi)
    return {
        "cgroup": str(group),
        "state": str(tmp_path / "state/pressure.json"),
        "systemPressure": str(tmp_path / "system.pressure"),
        "notify": str(tmp_path / "notify"),
        "policy": {
            "memoryHigh": 800,
            "memoryMax": 1000,
            "swapMax": 1000,
            "pressurePercent": 5,
            "nearLimitRatio": 0.9,
            "samples": 2,
            "cooldownSeconds": 900,
            "maxSampleGapSeconds": 105,
        },
    }


def test_pressure_debounce_cooldown_recovery_and_cold_swap(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Cold swap stays quiet; sustained near-limit usage notifies once."""
    config = pressure_config(tmp_path, monkeypatch)
    clock = PRESSURE["run"].__globals__["time"]
    monkeypatch.setattr(clock, "time", lambda: 2000.0)
    monitor = PRESSURE["run"]
    notices = tmp_path / "notices"
    for _ in range(3):
        monitor(config)
    assert not notices.exists()
    (tmp_path / "cgroup/memory.current").write_text("950\n")
    monitor(config)
    assert not notices.exists()
    monitor(config)
    monitor(config)
    assert len(notices.read_text().splitlines()) == 1
    monkeypatch.setattr(clock, "time", lambda: 3000.0)
    monitor(config)
    assert len(notices.read_text().splitlines()) == 1
    monitor(config)
    assert len(notices.read_text().splitlines()) == 2
    (tmp_path / "cgroup/memory.current").write_text("100\n")
    monitor(config)
    assert (
        json.loads(Path(config["state"]).read_text(encoding="utf-8"))["codex"]["count"]
        == 0
    )
    assert Path(config["state"]).stat().st_mode & 0o777 == 0o600


def test_system_pressure_with_absent_application(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """System stalls notify even when Codex is closed; no process is killed."""
    config = pressure_config(tmp_path, monkeypatch)
    config["cgroup"] = str(tmp_path / "absent")
    (tmp_path / "system.pressure").write_text(
        "full avg10=9.00 avg60=6.00 avg300=1.00 total=100000\n"
    )
    for _ in range(2):
        PRESSURE["run"](config)
    notices = (tmp_path / "notices").read_text().splitlines()
    assert len(notices) == 1
    assert "System memory stalls" in notices[0]


def test_cleanup_rejects_record_outside_runtime(tmp_path: Path) -> None:
    """A damaged ownership record cannot remove an unrelated policy file."""
    launch = runpy.run_path(str(SCRIPTS / "codex_launch.py"))
    outside = tmp_path / "unrelated/90-codex-slice.conf"
    outside.parent.mkdir()
    outside.write_text("keep this file", encoding="utf-8")
    state = tmp_path / "state"
    state.mkdir()
    (state / "policy.json").write_text(
        json.dumps({"path": str(outside), "content": "keep this file"}),
        encoding="utf-8",
    )
    with pytest.raises(RuntimeError, match="ownership record"):
        launch["cleanup"](state, tmp_path)
    assert outside.read_text(encoding="utf-8") == "keep this file"


def test_cleanup_preserves_foreign_pid_policy(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A failed exclusive install cannot stop the foreign policy's scope."""
    executable(tmp_path, "systemctl", "resource_systemctl.py")
    monkeypatch.delenv("RUNTIME_DIRECTORY", raising=False)
    monkeypatch.delenv("CODEX_LAUNCH_UNIT", raising=False)
    events = tmp_path / "events"
    monkeypatch.setenv("PATH", str(tmp_path) + os.pathsep + os.environ["PATH"])
    monkeypatch.setenv("CODEX_TEST_EVENTS", str(events))
    policy = (
        tmp_path
        / "systemd/user/app-org.chromium.Chromium-123.scope.d/90-codex-slice.conf"
    )
    policy.parent.mkdir(parents=True)
    policy.write_text("foreign policy", encoding="utf-8")
    state = tmp_path / "state"
    state.mkdir()
    (state / "policy.json").write_text(
        json.dumps({"path": str(policy), "content": "intended new policy"}),
        encoding="utf-8",
    )
    launch = runpy.run_path(str(SCRIPTS / "codex_launch.py"))
    launch["cleanup"](state, tmp_path, stop_scope=True)
    assert policy.read_text(encoding="utf-8") == "foreign policy"
    # Only the final manager reload ran; stopping the foreign scope would add
    # another recorded manager invocation.
    assert events.read_text(encoding="utf-8").splitlines() == ["reload"]


def test_pressure_history_attribution_and_counter_resets(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Warnings retain independent group evidence and discard stale baselines."""
    config = pressure_config(tmp_path, monkeypatch)
    group = tmp_path / "cgroup"
    for name in ("events", "events.local"):
        (group / ("memory." + name)).write_text("high 10\noom_kill 0\n")
    (group / "memory.swap.events").write_text("high 0\nmax 100\nfail 110\n")
    boot = tmp_path / "boot"
    boot.write_text("boot-a")
    (group / "memory.high").write_text("800\n")
    (tmp_path / "meminfo").write_text("MemAvailable: 1234 kB\n")
    config.update({
        "history": str(tmp_path / "history.jsonl"),
        "historyMaxBytes": 16384,
        "bootId": str(boot),
        "meminfo": str(tmp_path / "meminfo"),
        "observedGroups": {
            "queued-work": str(group),
            "absent": str(tmp_path / "absent"),
        },
    })
    clock = PRESSURE["run"].__globals__["time"]
    monkeypatch.setattr(clock, "time", lambda: 2000.0)
    monitor = PRESSURE["run"]
    monitor(config)
    (group / "memory.events.local").write_text("high 15\noom_kill 0\n")
    (group / "memory.events").write_text("high 19\noom_kill 1\n")
    (group / "memory.swap.events").write_text("high 0\nmax 125\nfail 140\n")
    psi = "some avg10=9.00 avg60=8.00 avg300=1.00 total=200000\nfull avg10=9.00 avg60=6.00 avg300=1.00 total=100000\n"
    (group / "memory.pressure").write_text(psi)
    (tmp_path / "system.pressure").write_text(psi)
    monkeypatch.setattr(clock, "time", lambda: 2030.0)
    monitor(config)
    sample = json.loads(Path(config["state"]).read_text(encoding="utf-8"))["sample"]
    assert sample["eventDeltas"]["queued-work"] == {
        "events": {"high": 9, "oom_kill": 1},
        "events.local": {"high": 5, "oom_kill": 0},
        "swap.events": {"high": 0, "max": 25, "fail": 30},
    }
    assert sample["groups"]["queued-work"]["swap.events"] == {
        "high": 0,
        "max": 125,
        "fail": 140,
    }
    assert sample["groups"]["absent"] is None
    assert sample["groups"]["queued-work"]["limits"]["high"] == "800"
    assert sample["availableMemory"] == 1234 * 1024
    assert sample["systemPsi"]["some"] == 8
    monkeypatch.setattr(clock, "time", lambda: 2060.0)
    monitor(config)
    assert "queued-work: 6.0%" in (tmp_path / "notices").read_text()
    history = Path(config["history"])
    assert len(history.read_text(encoding="utf-8").splitlines()) == 3
    assert history.stat().st_mode & 0o777 == 0o600
    # A reboot must not produce deltas or suppress warnings using old uptime.
    boot.write_text("boot-b")
    monitor(config)
    sample = json.loads(Path(config["state"]).read_text(encoding="utf-8"))["sample"]
    assert sample["eventDeltas"]["queued-work"] == {}
    current = PRESSURE["read_group"](group)
    previous = {**current, "identity": current["identity"] + 1}
    assert PRESSURE["event_delta"](current, previous) == {}
    previous = {**current, "events": {"high": 100, "oom_kill": 1}}
    assert PRESSURE["event_delta"](current, previous) == {}
    previous = {**current, "swap.events": {"high": 0, "max": 130, "fail": 150}}
    assert PRESSURE["event_delta"](current, previous) == {}
    (group / "memory.swap.events").unlink()
    assert PRESSURE["read_group"](group)["swap.events"] == {}


def test_history_rotation_preserves_two_private_bounded_files(tmp_path: Path) -> None:
    """Repeated samples have a fixed disk bound and retain the newest record."""
    path = tmp_path / "history.jsonl"
    append = PRESSURE["append_history"]
    for number in range(10):
        append(path, {"number": number}, 40)
    assert json.loads(path.read_text().splitlines()[-1]) == {"number": 9}
    assert sorted(p.name for p in tmp_path.iterdir()) == [
        "history.jsonl",
        "history.jsonl.1",
    ]
    assert all(p.stat().st_size <= 40 for p in tmp_path.iterdir())
    assert all(p.stat().st_mode & 0o777 == 0o600 for p in tmp_path.iterdir())


def test_monitor_upgrade_preserves_cooldown_and_clock_recovery(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """An upgrade stays quiet; a backward clock step cannot suppress indefinitely."""
    config = pressure_config(tmp_path, monkeypatch)
    (tmp_path / "system.pressure").write_text(
        "full avg10=9.00 avg60=6.00 avg300=1.00 total=100000\n"
    )
    state = Path(config["state"])
    state.parent.mkdir()
    state.write_text(
        json.dumps({
            "system": {"count": 2, "notified": 1999},
            "sample": {"time": 1970},
        }),
        encoding="utf-8",
    )
    clock = PRESSURE["run"].__globals__["time"]
    monkeypatch.setattr(clock, "time", lambda: 2000.0)
    for _ in range(2):
        PRESSURE["run"](config)
    assert not (tmp_path / "notices").exists()
    monkeypatch.setattr(clock, "time", lambda: 1000.0)
    for _ in range(2):
        PRESSURE["run"](config)
    assert len((tmp_path / "notices").read_text().splitlines()) == 1


def test_recreated_codex_group_starts_its_own_warning_window(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Two different group generations cannot combine into sustained pressure."""
    config = pressure_config(tmp_path, monkeypatch)
    (tmp_path / "cgroup/memory.current").write_text("950\n")
    PRESSURE["run"](config)
    replacement = tmp_path / "replacement"
    replacement.mkdir()
    for name in ("memory.current", "memory.swap.current", "memory.pressure"):
        (replacement / name).write_text((tmp_path / "cgroup" / name).read_text())
    config["cgroup"] = str(replacement)
    PRESSURE["run"](config)
    assert not (tmp_path / "notices").exists()
    PRESSURE["run"](config)
    assert len((tmp_path / "notices").read_text().splitlines()) == 1


def history_rows(path: Path, table: str) -> list[dict]:
    """Decode retained records for behavioral assertions.

    Returns:
        Chronologically ordered diagnostic records.

    """
    with contextlib.closing(sqlite3.connect(path)) as db:
        rows = db.execute(f"SELECT data FROM {table} ORDER BY time").fetchall()  # ruff: ignore[hardcoded-sql-expression] -- Test-selected constant table names.
    return [json.loads(zlib.decompress(row[0])) for row in rows]


def history_sample(now: float, **extra: object) -> dict:
    """Create an independent host snapshot without live process data.

    Returns:
        Minimal valid retained sample.

    """
    return {
        "time": now,
        "boot": "boot-a",
        "systemPressure": 0,
        "availableMemory": 1000,
        "codex": None,
        "groups": {},
        "eventDeltas": {},
        **extra,
    }


def test_transactional_history_expiry_clock_and_peaks(tmp_path: Path) -> None:
    """Raw expiry preserves summaries; clock rollback removes future evidence."""
    path = tmp_path / "history.sqlite"
    config = {"database": str(path), "rawSeconds": 60, "summarySeconds": 600}
    retain = PRESSURE["retain_history"]
    old = history_sample(1000, systemPressure=8)
    retain(config, old, {}, False)
    newer = history_sample(1030, systemPressure=2, availableMemory=500)
    retain(config, newer, old, True)
    bucket = history_rows(path, "summary")[0]
    assert bucket["samples"] == 2
    assert bucket["hostFullMax"] == 8
    assert bucket["availableMin"] == 500
    retain(config, history_sample(1100), newer, True)
    assert [r["time"] for r in history_rows(path, "raw")] == [1100]
    assert len(history_rows(path, "summary")) == 1
    retain(config, history_sample(1700), {}, False)
    assert len(history_rows(path, "summary")) == 1
    retain(config, history_sample(1000, systemPressure=1), {"time": 1700}, False)
    assert [r["time"] for r in history_rows(path, "raw")] == [1000]
    assert history_rows(path, "summary")[0]["hostFullMax"] == 1
    assert path.stat().st_mode & 0o777 == 0o600


def test_history_capacity_retains_newest_and_bounded_database(tmp_path: Path) -> None:
    """Compression and capacity eviction keep new evidence within the allowance."""
    path = tmp_path / "history.sqlite"
    allowance = 256 * 1024
    config = {"database": str(path), "historyTotalBytes": allowance}
    generator = random.Random(0)  # ruff: ignore[suspicious-non-cryptographic-random-usage] -- Deterministic incompressible test fixture.
    for number in range(30):
        sample = history_sample(1000 + number, fixture=generator.randbytes(8192).hex())
        PRESSURE["retain_history"](config, sample, {}, False)
    rows = history_rows(path, "raw")
    assert rows[-1]["time"] == 1029
    assert len(rows) < 30
    assert sum(p.stat().st_size for p in tmp_path.iterdir()) <= allowance
    assert not Path(str(path) + "-journal").exists()
    assert history_rows(path, "summary")[0]["samples"] == 30


def test_summary_deltas_do_not_cross_group_generations() -> None:
    """Restarts retain peaks without inventing stall duration or summing counters."""
    group = {
        "identity": 1,
        "memory": 100,
        "swap": 10,
        "pressure": 3,
        "psi": {"someTotal": 100, "fullTotal": 50},
    }
    old = history_sample(1000, groups={"app": group})
    sample = history_sample(
        1030,
        groups={"app": {**group, "psi": {"someTotal": 200, "fullTotal": 80}}},
        eventDeltas={"app": {"events": {"high": 9}, "events.local": {"high": 2}}},
    )
    row = PRESSURE["summary"](sample, old, True, {})["groups"]["app"]
    assert row["fullMicroseconds"] == 30
    assert row["fullObservedSeconds"] == 30
    assert row["events"]["high"] == 9
    assert row["events.local"]["high"] == 2
    sample["groups"]["app"]["identity"] = 2
    row = PRESSURE["summary"](sample, old, True, {})["groups"]["app"]
    assert "fullMicroseconds" not in row


def test_paging_and_zram_use_physical_units_and_reset_baselines(tmp_path: Path) -> None:
    """Paging rates reset with counters; zram physical cost stays distinct."""
    vmstat = tmp_path / "vmstat"
    vmstat.write_text("pswpin 20\npswpout 40\npgmajfault 8\n")
    zram = tmp_path / "mm_stat"
    zram.write_text("3000 900 1000 0 2000\n")
    config = {"vmstat": str(vmstat), "zramStat": str(zram)}
    old = {
        "time": 10,
        "paging": {"counters": {"pswpin": 10, "pswpout": 20, "pgmajfault": 4}},
    }
    assert PRESSURE["paging"](config, old, True, 20)["perSecond"] == {
        "pswpin": 1,
        "pswpout": 2,
        "pgmajfault": 0.4,
    }
    assert PRESSURE["paging"](config, old, False, 20)["perSecond"] is None
    vmstat.write_text("pswpin 0\npswpout 0\npgmajfault 0\n")
    assert PRESSURE["paging"](config, old, True, 20)["perSecond"] is None
    assert PRESSURE["zram"](config) == {
        "originalBytes": 3000,
        "compressedBytes": 900,
        "allocatedBytes": 1000,
    }


def test_unwritable_history_does_not_suppress_pressure_notifications(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Storage failure remains visible while current host warnings still work."""
    config = pressure_config(tmp_path, monkeypatch)
    config["database"] = str(tmp_path / "directory")
    Path(config["database"]).mkdir()
    (tmp_path / "system.pressure").write_text(
        "full avg10=9 avg60=6 avg300=1 total=100\n"
    )
    for _ in range(2):
        PRESSURE["run"](config)
    assert (tmp_path / "notices").exists()
    state = json.loads(Path(config["state"]).read_text(encoding="utf-8"))
    assert state["sample"]["historyError"] == "IsADirectoryError"


def test_zen_session_preserves_arguments_and_uses_shared_slice(tmp_path: Path) -> None:
    """A portal launch uses the real executable and preserves URL data literally."""
    source = ROOT / "homes/desktop/local/browsers/scripts/zen-session.sh.in"
    sink = tmp_path / "args.json"
    uwsm = tmp_path / "systemd-run"
    uwsm.write_text(
        "#!"
        + sys.executable
        + "\nimport json,sys\nfrom pathlib import Path\nPath("
        + repr(str(sink))
        + ").write_text(json.dumps(sys.argv[1:]))\n"
    )
    uwsm.chmod(0o700)
    script = tmp_path / "zen-session"
    script.write_text(
        source
        .read_text()
        .replace("@bash@", "/bin/bash")
        .replace("@systemdRun@", str(uwsm))
        .replace("@browser@", "/fixture/zen-beta")
    )
    args = [
        "--private-window",
        "https://example.test/?q=$value&x=`literal`&home=${HOME}&cash=$$",
        "two words",
    ]
    bash = shutil.which("bash")
    assert bash is not None
    result = subprocess.run([bash, str(script), *args], check=False)
    assert result.returncode == 0
    assert json.loads(sink.read_text()) == [
        "--user",
        "--scope",
        "--collect",
        "--quiet",
        "--expand-environment=no",
        "--slice=app-zen.slice",
        "--property=OOMPolicy=continue",
        "--property=PartOf=graphical-session.target",
        "--property=After=graphical-session.target",
        "--",
        "/fixture/zen-beta",
        *args,
    ]


def test_pattern_discovery_drops_old_missing_scopes(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A vanished application is unavailable for one sample, never immortal state."""
    config = pressure_config(tmp_path, monkeypatch)
    root = tmp_path / "apps"
    root.mkdir()
    group = root / "app-fixture.scope"
    shutil.copytree(tmp_path / "cgroup", group)
    config["observedPatterns"] = {"gui": {"root": str(root), "pattern": "app-*.scope"}}
    first = PRESSURE["collect"](config, {}, False)
    assert first["groups"]["gui/app-fixture.scope"] is not None
    shutil.rmtree(group)
    second = PRESSURE["collect"](config, first, True)
    assert second["groups"]["gui/app-fixture.scope"] is None
    third = PRESSURE["collect"](config, second, True)
    assert "gui/app-fixture.scope" not in third["groups"]
    assert third["groups"]["gui"] is None


def test_history_keeps_fourteen_days_of_representative_summaries(
    tmp_path: Path,
) -> None:
    """Serialized eight-group history fits the documented default retention budget."""
    config = {
        "database": str(tmp_path / "history.sqlite"),
        "historyTotalBytes": 30 * 1024 * 1024,
    }
    group = {
        "identity": 1,
        "memory": 123456789,
        "swap": 23456789,
        "pressure": 2,
        "psi": {"someTotal": 100, "fullTotal": 50},
    }
    previous = {}
    # Thirteen days of five-minute summaries, followed by one day of raw detail.
    times = [*range(0, 13 * 86400, 300), *range(13 * 86400, 14 * 86400, 30)]
    for now in times:
        sample = history_sample(
            now,
            groups={f"group-{n}": group for n in range(8)},
            zram={"originalBytes": 8000000, "allocatedBytes": 3000000},
        )
        PRESSURE["retain_history"](config, sample, previous, bool(previous))
        previous = sample
    rows = history_rows(Path(config["database"]), "summary")
    assert len(rows) == 14 * 24 * 12
    assert rows[0]["first"] == 0
    assert rows[-1]["last"] == 14 * 86400 - 30
    assert len(history_rows(Path(config["database"]), "raw")) >= 2880
    assert (
        sum(p.stat().st_size for p in tmp_path.iterdir()) <= config["historyTotalBytes"]
    )


def test_history_rejects_symlink_without_modifying_target(tmp_path: Path) -> None:
    """A history pathname cannot redirect writes into another file."""
    target = tmp_path / "keep"
    target.write_text("preserve")
    link = tmp_path / "history.sqlite"
    link.symlink_to(target)
    with pytest.raises(OSError, match="Too many levels"):
        PRESSURE["retain_history"](
            {"database": str(link)}, history_sample(1000), {}, False
        )
    assert target.read_text() == "preserve"
