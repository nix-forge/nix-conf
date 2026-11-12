"""Capacity waits must not reserve execution; launch still owns every lock."""

import argparse
import fcntl
import importlib.util
import json
import os
import re
import shutil
import signal
import subprocess  # ruff: ignore[suspicious-subprocess-import] - only owned fixture processes
import sys
import time
from pathlib import Path
from types import SimpleNamespace

import pytest

SOURCE = (
    Path(__file__).parents[2]
    / "modules/home/services/workstation-jobs-assets/workstation_memory.py"
)
SPEC = importlib.util.spec_from_file_location("admission_locks", SOURCE)
assert SPEC
assert SPEC.loader
memory = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(memory)
MIB = 1024**2


def test_blocked_daemon_does_not_hold_bulk_execution(tmp_path: Path) -> None:
    """Run the real supervisor/controller with a short host-capacity fixture."""
    commands = tmp_path / "bin"
    commands.mkdir()
    manager = commands / "systemctl"
    manager.write_text(
        '#!/bin/sh\ncase "$*" in *MemoryHigh*) '
        "printf 'MemoryHigh=9\\nMemoryMax=10\\nMemorySwapMax=0\\nManagedOOMMemoryPressure=kill\\n';; esac\n"
    )
    manager.chmod(0o700)
    runtime = tmp_path / "runtime"
    runtime.mkdir()
    meminfo = tmp_path / "meminfo"
    meminfo.write_text("MemAvailable: 12582912 kB\n")
    bulk_lock = tmp_path / "bulk.lock"
    values = {
        "boundedMemoryMinGiB": "1",
        "boundedMemoryMaxGiB": "8",
        "boundedReserve": str(2 * 1024**3),
        "boundedHighPercent": "90",
        "memoryHigh": "9",
        "memoryMax": "10",
        "memorySwapMax": "0",
        "bulkMemoryAvailable": str(14 * 1024**3),
        "admissionSeconds": "5",
        "admissionHealthySeconds": "0",
        "admissionPressureLimit": "50",
        "memoryController": f"{sys.executable} {SOURCE}",
        "bulkLock": str(bulk_lock),
        "diskAdmission": "true",
        "taskEvents": "true",
    }
    shell = SOURCE.parents[4] / "homes/desktop/local/workstation-task.sh"
    rendered = re.sub(r"@(\w+)@", lambda m: values.get(m[1], "0"), shell.read_text())
    rendered = rendered.replace("/proc/meminfo", str(meminfo))
    # Model a new caller even when pytest itself runs in a managed allocation.
    caller_group = tmp_path / "caller-cgroup"
    caller_group.write_text("0::/fixture-unmanaged\n")
    rendered = rendered.replace("/proc/self/cgroup", str(caller_group))
    script = tmp_path / "runner.sh"
    script.write_text(rendered)
    # A controller fixture must never inherit its enclosing durable job receipt.
    process = subprocess.Popen(  # ruff: ignore[subprocess-without-shell-equals-true] - fixed fixture argv
        [str(shutil.which("bash")), str(script), "true"],
        env={
            **{
                key: value
                for key, value in os.environ.items()
                if not key.startswith("WORKSTATION_")
            },
            "PATH": f"{commands}:{os.environ['PATH']}",
            "XDG_RUNTIME_DIR": str(runtime),
        },
        start_new_session=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    try:
        deadline = time.monotonic() + 3
        while True:
            receipts = list(runtime.glob("workstation-task-allocations/*.json")) + list(
                runtime.glob("workstation-task-allocations/*.tmp")
            )
            if (
                receipts
                and json.loads(receipts[0].read_text())["phase"] == "waiting-capacity"
            ):
                break
            assert process.poll() is None, process.communicate()
            assert time.monotonic() < deadline, "No capacity wait receipt"
            time.sleep(0.01)
        with bulk_lock.open("a") as contender:
            fcntl.flock(contender, fcntl.LOCK_EX | fcntl.LOCK_NB)
            fcntl.flock(contender, fcntl.LOCK_UN)
            # A smaller real controller can grant while the daemon still waits.
            pressure = tmp_path / "quiet-pressure"
            pressure.write_text("full avg10=0.00\n")
            result = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - fixed controller argv
                [
                    sys.executable,
                    str(SOURCE),
                    "admit",
                    "--receipt",
                    str(tmp_path / "peer.json"),
                    "--minimum",
                    "8192",
                    "--maximum",
                    "8192",
                    "--reserve",
                    "2048",
                    "--healthy-seconds",
                    "0",
                    "--meminfo",
                    str(meminfo),
                    "--pressure",
                    str(pressure),
                    "--lock-fd",
                    str(contender.fileno()),
                ],
                pass_fds=(contender.fileno(),),
                capture_output=True,
                text=True,
                check=True,
                timeout=3,
            )
            assert result.stdout == "8192\n"
            assert process.poll() is None
    finally:
        process.terminate()
        try:
            process.communicate(timeout=3)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.communicate(timeout=3)


@pytest.mark.parametrize("cancel_at_grant", [False, True])
def test_memory_wait_releases_reservation_and_rechecks_before_launch(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, *, cancel_at_grant: bool
) -> None:
    """A fitting contender can run, and changed capacity cannot pass admission."""
    lock = tmp_path / "execution.lock"
    owner = lock.open("w")
    contender = lock.open("w")
    # Initially short, then ready; the under-lock sample sees lost capacity.
    samples = iter([0, 8, 0, 8, 8])
    observed_waits = []

    def sample(*_args: object) -> dict:
        return {"availableBytes": next(samples) * MIB}

    def wait(_seconds: float) -> None:
        fcntl.flock(contender, fcntl.LOCK_EX | fcntl.LOCK_NB)
        observed_waits.append(True)
        fcntl.flock(contender, fcntl.LOCK_UN)

    monkeypatch.setattr(memory, "snapshot", sample)
    monkeypatch.setattr(
        memory,
        "Notifications",
        lambda *_: SimpleNamespace(wait=wait, close=lambda: None),
    )
    args = argparse.Namespace(
        receipt=tmp_path / "receipt.json",
        timeout=5,
        minimum=8,
        maximum=8,
        reserve=0,
        quantum=1,
        pressure_limit=50,
        healthy_seconds=0,
        pressure=tmp_path,
        group=None,
        root=tmp_path,
        meminfo=tmp_path,
        lock_fd=[owner.fileno()],
    )
    original_save = memory.save

    def cancel_save(path: Path, record: dict) -> None:
        if record["phase"] == "admitted":
            raise SystemExit(143)
        original_save(path, record)

    try:
        if cancel_at_grant:
            monkeypatch.setattr(memory, "save", cancel_save)
            with pytest.raises(SystemExit):
                memory.admit(args)
            fcntl.flock(contender, fcntl.LOCK_EX | fcntl.LOCK_NB)
        else:
            assert memory.admit(args) == 0
            with pytest.raises(BlockingIOError):
                fcntl.flock(contender, fcntl.LOCK_EX | fcntl.LOCK_NB)
        assert observed_waits == [True, True]
    finally:
        owner.close()
        contender.close()


def test_busy_peer_releases_partial_locks(tmp_path: Path) -> None:
    """A legacy peer holding the last lock cannot cause a lock-order deadlock."""
    with (
        (tmp_path / "bulk").open("w") as bulk,
        (tmp_path / "private").open("w") as private,
        (tmp_path / "bulk").open("a") as bulk_peer,
        (tmp_path / "private").open("a") as private_peer,
    ):
        fcntl.flock(private_peer, fcntl.LOCK_EX)
        assert not memory.reserve_execution([bulk.fileno(), private.fileno()])
        fcntl.flock(bulk_peer, fcntl.LOCK_EX | fcntl.LOCK_NB)
        with pytest.raises(BlockingIOError):
            fcntl.flock(private, fcntl.LOCK_EX | fcntl.LOCK_NB)


def test_invalid_reservation_releases_partial_locks(tmp_path: Path) -> None:
    """Bad inherited descriptors fail closed without stranding an earlier lock."""
    with (tmp_path / "bulk").open("w") as bulk, (tmp_path / "bulk").open("a") as peer:
        with pytest.raises(ValueError, match="negative"):
            memory.reserve_execution([bulk.fileno(), -1])
        fcntl.flock(peer, fcntl.LOCK_EX | fcntl.LOCK_NB)


def test_controller_exit_leaves_execution_owned_by_supervisor(tmp_path: Path) -> None:
    """The actual CLI grant retains the parent's reservation after child exit."""
    meminfo = tmp_path / "meminfo"
    meminfo.write_text("MemAvailable: 20971520 kB\n")
    pressure = tmp_path / "pressure"
    pressure.write_text("full avg10=0.00\n")
    with (tmp_path / "bulk").open("w") as owner, (tmp_path / "bulk").open("a") as peer:
        result = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - fixed owned CLI argv
            [
                sys.executable,
                str(SOURCE),
                "admit",
                "--receipt",
                str(tmp_path / "receipt.json"),
                "--minimum",
                "8192",
                "--maximum",
                "8192",
                "--reserve",
                "2048",
                "--healthy-seconds",
                "0",
                "--meminfo",
                str(meminfo),
                "--pressure",
                str(pressure),
                "--lock-fd",
                str(owner.fileno()),
            ],
            pass_fds=(owner.fileno(),),
            capture_output=True,
            text=True,
            check=True,
            timeout=3,
        )
        assert result.stdout == "8192\n"
        with pytest.raises(BlockingIOError):
            fcntl.flock(peer, fcntl.LOCK_EX | fcntl.LOCK_NB)
        fcntl.flock(owner, fcntl.LOCK_UN)
        fcntl.flock(peer, fcntl.LOCK_EX | fcntl.LOCK_NB)
