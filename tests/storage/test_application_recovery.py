"""Exercise application semantics, writer restart and failed drill receipts."""

from __future__ import annotations

import fcntl
import json
import os
import runpy
import shutil
import sqlite3
import subprocess
import sys
import time
from pathlib import Path
from typing import TYPE_CHECKING

import pytest

if TYPE_CHECKING:
    from typing import Any

RUNNER = (
    Path(__file__).parents[2] / "modules/nixos/services/application-recovery/runner.py"
)
HELPER = runpy.run_path(str(RUNNER))


def policy(tmp_path: Path) -> dict[str, Any]:
    """Build a recipe whose effects stay in test temporary storage.

    Returns:
        A declared application lifecycle.

    """
    return {
        "stateDirectory": str(tmp_path / "state"),
        "units": [],
        "timeoutSeconds": 10,
        **{
            phase: [sys.executable, "-c", "pass"]
            for phase in ("export", "backup", "recover", "restore", "check")
        },
    }


def test_sqlite_and_vm_state_roundtrip(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Restore committed WAL records and VM artifacts from real disposable Restic."""
    assert shutil.which("restic"), "The test environment must provide Restic"
    source = tmp_path / "source"
    source.mkdir()
    vm = source / "vm"
    (vm / "tpm").mkdir(parents=True)
    (vm / "domain.xml").write_text(
        "<domain><uuid>de305d54-75b4-431b-adb2-eb6b9e546014</uuid></domain>"
    )
    (vm / "firmware.fd").write_bytes(b"fixture-firmware-generation-2")
    (vm / "tpm/state").write_bytes(b"fixture-tpm-generation-2")
    (vm / "disk.raw").write_bytes(b"fixture-guest-persisted-generation-2")
    monkeypatch.setenv("FIXTURE_SOURCE", str(source))
    monkeypatch.setenv("RESTIC_REPOSITORY", str(tmp_path / "repository"))
    monkeypatch.setenv("RESTIC_PASSWORD", "disposable-fixture")
    monkeypatch.setenv("RESTIC_CACHE_DIR", str(tmp_path / "cache"))
    subprocess.run(
        [str(shutil.which("restic")), "init"], check=True, capture_output=True
    )
    recipe = policy(tmp_path)
    for phase in ("export", "backup", "recover", "restore", "check"):
        recipe[phase] = [
            sys.executable,
            str(Path(__file__).with_name("application_fixture.py")),
            phase,
        ]
    with sqlite3.connect(source / "app.sqlite") as database:
        database.execute("PRAGMA journal_mode=WAL")
        database.execute("CREATE TABLE records (name TEXT PRIMARY KEY, value INTEGER)")
        database.execute("INSERT INTO records VALUES ('initial', 7)")
        database.commit()
        database.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        database.execute("INSERT INTO records VALUES ('after-checkpoint', 42)")
        database.commit()
        HELPER["execute"](recipe, "backup")
    # Remove every source artifact; restoration cannot accidentally check originals.
    shutil.rmtree(source)
    HELPER["execute"](recipe, "drill")
    success = tmp_path / "state/drill-success.json"
    assert json.loads(success.read_text())["scope"] == "isolated-application-drill"
    old_success = success.read_bytes()
    recipe["check"] = [sys.executable, "-c", "raise SystemExit(1)"]
    with pytest.raises(subprocess.CalledProcessError):
        HELPER["execute"](recipe, "drill")
    assert success.read_bytes() == old_success
    assert (
        json.loads((tmp_path / "state/drill-attempt.json").read_text())["result"]
        == "failure"
    )
    assert not list((tmp_path / "state").glob("operation-*"))


@pytest.mark.parametrize("failure_phase", ["export", "backup"])
def test_failed_phase_restarts_running_writers(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, failure_phase: str
) -> None:
    """A stopped running writer resumes after failure; an inactive writer stays inactive."""
    adapter = tmp_path / "systemctl"
    events = tmp_path / "events"
    adapter.write_text(f"""#!{sys.executable}
import pathlib,sys
p = pathlib.Path({str(events)!r})
action, unit = sys.argv[1:3]
if action == 'show':
    print('LoadState=loaded\\nActiveState=' + ('active' if unit == 'writer.service' else 'inactive'))
elif action in ('stop', 'start'):
    p.open('a').write(action + ' ' + unit + '\\n')
else:
    raise SystemExit(9)
""")
    adapter.chmod(0o755)
    monkeypatch.setenv("PATH", str(tmp_path) + os.pathsep + os.environ["PATH"])
    recipe = policy(tmp_path)
    recipe["units"] = ["writer.service", "inactive.service"]
    recipe[failure_phase] = [sys.executable, "-c", "raise SystemExit(1)"]
    with pytest.raises(subprocess.CalledProcessError):
        HELPER["execute"](recipe, "backup")
    assert events.read_text().splitlines() == [
        "stop writer.service",
        "start writer.service",
    ]
    assert not (tmp_path / "state/backup-success.json").exists()


def test_concurrent_operation_cannot_overlap(tmp_path: Path) -> None:
    """A held application lock rejects a second operation without running hooks."""
    recipe = policy(tmp_path)
    state = Path(recipe["stateDirectory"])
    state.mkdir()
    with (state / "operation.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        with pytest.raises(HELPER["RecoveryError"], match="already running"):
            HELPER["execute"](recipe, "backup")
    assert not (state / "backup-success.json").exists()


@pytest.mark.parametrize("failure_mode", ["nonzero", "unfinished-child"])
def test_restart_failure_attempts_other_writers(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, failure_mode: str
) -> None:
    """One failed restart cannot prevent recovery attempts for other stopped writers."""
    events = tmp_path / "events"
    adapter = tmp_path / "systemctl"
    adapter.write_text(f"""#!{sys.executable}
import pathlib,sys,subprocess
action, unit = sys.argv[1:3]
if action == 'show':
    print('LoadState=loaded\\nActiveState=active')
elif action in ('stop', 'start'):
    pathlib.Path({str(events)!r}).open('a').write(action + ' ' + unit + '\\n')
    if action == 'start' and unit == 'second.service':
        if {failure_mode!r} == 'nonzero':
            raise SystemExit(1)
        subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(10)'])
else:
    raise SystemExit(9)
""")
    adapter.chmod(0o755)
    monkeypatch.setenv("PATH", str(tmp_path) + os.pathsep + os.environ["PATH"])
    recipe = policy(tmp_path)
    recipe["units"] = ["first.service", "second.service"]
    with pytest.raises(HELPER["RecoveryError"], match="could not restart"):
        HELPER["execute"](recipe, "backup")
    assert events.read_text().splitlines()[-2:] == [
        "start second.service",
        "start first.service",
    ]
    assert not (tmp_path / "state/backup-success.json").exists()


def test_sigterm_resumes_writer_before_exit(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Cancellation reaches the runner first and cannot skip its writer cleanup."""
    events = tmp_path / "events"
    started = tmp_path / "export-started"
    adapter = tmp_path / "systemctl"
    adapter.write_text(f"""#!{sys.executable}
import pathlib,sys
if sys.argv[1] == 'show':
    print('LoadState=loaded\\nActiveState=active')
elif sys.argv[1] in ('stop', 'start'):
    pathlib.Path({str(events)!r}).open('a').write(sys.argv[1] + '\\n')
else:
    raise SystemExit(9)
""")
    adapter.chmod(0o755)
    monkeypatch.setenv("PATH", str(tmp_path) + os.pathsep + os.environ["PATH"])
    recipe = policy(tmp_path)
    recipe["units"] = ["writer.service"]
    recipe["export"] = [
        sys.executable,
        "-c",
        f"import pathlib,time; pathlib.Path({str(started)!r}).touch(); time.sleep(60)",
    ]
    config = tmp_path / "policy.json"
    config.write_text(json.dumps(recipe))
    with subprocess.Popen(
        [sys.executable, str(RUNNER), str(config), "backup"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    ) as process:
        try:
            deadline = time.monotonic() + 5
            while not started.exists() and time.monotonic() < deadline:
                time.sleep(0.02)
            assert started.exists(), "Export never started"
            process.terminate()
            process.communicate(timeout=5)
            assert process.returncode == 1
        finally:
            process.kill()
            process.wait()
    assert events.read_text().splitlines() == ["stop", "start"]
    assert (
        json.loads((tmp_path / "state/backup-attempt.json").read_text())["result"]
        == "failure"
    )


def test_async_export_cannot_certify_a_backup(tmp_path: Path) -> None:
    """A leader that exits before its delayed writer finishes cannot succeed."""
    delayed = tmp_path / "late-export"
    backed_up = tmp_path / "backup-ran"
    child = (
        f"import pathlib,time; time.sleep(0.4); pathlib.Path({str(delayed)!r}).touch()"
    )
    recipe = policy(tmp_path)
    recipe["export"] = [
        sys.executable,
        "-c",
        f"import subprocess,sys; subprocess.Popen([sys.executable, '-c', {child!r}])",
    ]
    recipe["backup"] = [
        sys.executable,
        "-c",
        f"import pathlib; pathlib.Path({str(backed_up)!r}).touch()",
    ]
    with pytest.raises(HELPER["RecoveryError"], match="unfinished child processes"):
        HELPER["execute"](recipe, "backup")
    assert not backed_up.exists()
    assert not (tmp_path / "state/backup-success.json").exists()
    # Wait past the child's intended mutation to prove cleanup stopped it.
    time.sleep(0.5)
    assert not delayed.exists()
    assert (
        json.loads((tmp_path / "state/backup-attempt.json").read_text())["result"]
        == "failure"
    )


def test_dependency_shutdown_preserves_original_running_set(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Stopping a parent must not hide a formerly active PartOf child from cleanup."""
    states = tmp_path / "unit-states.json"
    states.write_text(
        json.dumps({"parent.service": "active", "child.service": "active"})
    )
    adapter = tmp_path / "systemctl"
    adapter.write_text(f"""#!{sys.executable}
import pathlib,json,sys
path = pathlib.Path({str(states)!r})
state = json.loads(path.read_text())
action, unit = sys.argv[1:3]
if action == 'show':
    print('LoadState=loaded\\nActiveState=' + state[unit])
elif action == 'stop':
    state[unit] = 'inactive'
    if unit == 'parent.service':
        state['child.service'] = 'inactive'
    path.write_text(json.dumps(state))
elif action == 'start':
    state[unit] = 'active'
    path.write_text(json.dumps(state))
else:
    raise SystemExit(9)
""")
    adapter.chmod(0o755)
    monkeypatch.setenv("PATH", str(tmp_path) + os.pathsep + os.environ["PATH"])
    recipe = policy(tmp_path)
    recipe["units"] = ["parent.service", "child.service"]
    recipe["export"] = [sys.executable, "-c", "raise SystemExit(1)"]
    with pytest.raises(subprocess.CalledProcessError):
        HELPER["execute"](recipe, "backup")
    assert json.loads(states.read_text()) == {
        "parent.service": "active",
        "child.service": "active",
    }
