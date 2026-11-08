"""Check service freshness and delivery acknowledgement without a desktop session."""

from __future__ import annotations

import json
import os
import runpy
import select
import subprocess
import sys
import time
from pathlib import Path
from typing import TYPE_CHECKING

import pytest

pytestmark = pytest.mark.skipif(
    not hasattr(os, "pidfd_open"), reason="NixOS process supervision uses Linux pidfds"
)

if TYPE_CHECKING:
    from typing import Any

HELPER = runpy.run_path(
    str(Path(__file__).parents[2] / "hosts/nixos/desktop/local/storage/health.py")
)


def test_group_snapshot_accepts_arbitrary_process_name_bytes(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Parse numeric stat fields without interpreting unrelated comm bytes."""
    process = tmp_path / "123"
    process.mkdir()
    stat = process / "stat"
    stat.write_bytes(b"123 (fixture\xff) S 1 456 0\n")
    monkeypatch.setitem(
        HELPER["_unfinished_group"].__globals__, "Path", lambda _: tmp_path
    )
    assert not HELPER["_unfinished_group"](789)
    stat.write_bytes(b"123 (fixture\xff) S 1 789 0\n")
    assert HELPER["_unfinished_group"](789)


def test_finished_health_leader_cannot_leave_closed_pipe_descendants(
    tmp_path: Path,
) -> None:
    """Reject and terminate descendants even after their output pipes close."""
    child_file = tmp_path / "child.pid"
    fixture = Path(__file__).parents[1] / "process/fixtures/command.py"
    with pytest.raises(subprocess.SubprocessError, match="unfinished child processes"):
        HELPER["run"]([
            sys.executable,
            str(fixture),
            "closed-descendant",
            str(child_file),
        ])
    child = int(child_file.read_text(encoding="utf-8"))
    try:
        descriptor = os.pidfd_open(child)
    except ProcessLookupError:
        return
    try:
        assert select.select([descriptor], [], [], 1)[0]
    finally:
        os.close(descriptor)


def test_delivery_retries_failure_and_reports_recovery(tmp_path: Path) -> None:
    """Failed delivery must retry; successful warnings and recovery deduplicate."""
    log = tmp_path / "events"
    policy = {
        "stateDirectory": str(tmp_path),
        "notificationCommand": [
            sys.executable,
            str(Path(__file__).with_name("fixtures") / "failed_delivery.py"),
        ],
    }
    assert HELPER["deliver"](policy, ["Probe failed"]) == 1
    assert (tmp_path / "delivery/pending.json").exists()
    assert not (tmp_path / "delivery/delivered.json").exists()
    policy["notificationCommand"] = [
        sys.executable,
        str(Path(__file__).resolve().parents[1] / "fixtures/process.py"),
        "stdin-log",
        str(log),
    ]
    assert HELPER["deliver"](policy, ["Probe failed"]) == 0
    assert HELPER["deliver"](policy, ["Probe failed"]) == 0
    assert HELPER["deliver"](policy, []) == 0
    assert HELPER["deliver"](policy, []) == 0
    assert [json.loads(line)["event"] for line in log.read_text().splitlines()] == [
        "warning",
        "recovery",
    ]
    assert not (tmp_path / "delivery/pending.json").exists()


def test_no_channel_retains_warning_and_test_does_not_acknowledge_it(
    tmp_path: Path,
) -> None:
    """An absent channel retains warnings without failing the system unit."""
    policy = {"stateDirectory": str(tmp_path), "notificationCommand": None}
    assert HELPER["deliver"](policy, ["Missing backup"]) == 0
    assert (
        json.loads((tmp_path / "delivery/pending.json").read_text())["event"]
        == "warning"
    )
    assert HELPER["deliver"](policy, ["Missing backup"], test=True) == 1
    policy["notificationCommand"] = [
        sys.executable,
        str(Path(__file__).with_name("fixtures") / "successful_delivery.py"),
    ]
    assert HELPER["deliver"](policy, ["Missing backup"], test=True) == 0
    assert not (tmp_path / "delivery/delivered.json").exists()
    assert (
        json.loads((tmp_path / "delivery/pending.json").read_text())["event"]
        == "warning"
    )
    assert HELPER["deliver"](policy, []) == 0
    assert not (tmp_path / "delivery/pending.json").exists()


@pytest.mark.parametrize("completed", [0, float("nan"), float("inf"), 10**20])
def test_invalid_health_timestamp_is_stale(tmp_path: Path, completed: float) -> None:
    """Invalid and future collection dates cannot establish current monitoring."""
    (tmp_path / "health.json").write_text(
        json.dumps({"checked": completed, "messages": []})
    )
    assert HELPER["read"]({"stateDirectory": str(tmp_path)})


def test_probes_fail_closed_and_keep_output_private(tmp_path: Path) -> None:
    """A missing success receipt and failed command are distinct actionable probes."""
    receipt = tmp_path / "success.json"
    probes: dict[str, Any] = {
        "database-backup": {
            "command": [],
            "receipt": str(receipt),
            "maxAgeSeconds": 60,
            "timeoutSeconds": 1,
        },
        "service": {
            "command": [
                sys.executable,
                str(
                    Path(__file__).with_name("fixtures")
                    / "failed_probe_with_private_output.py"
                ),
            ],
            "receipt": None,
            "timeoutSeconds": 1,
        },
    }
    messages = HELPER["probe_messages"]({"probes": probes})
    assert len(messages) == len(probes)
    assert "private-token" not in str(messages)
    receipt.write_text(json.dumps({"completed": time.time(), "result": "success"}))
    assert (
        HELPER["probe_messages"]({
            "probes": {"database-backup": probes["database-backup"]}
        })
        == []
    )
    receipt.write_text(json.dumps({"completed": time.time(), "result": "failure"}))
    assert HELPER["probe_messages"]({
        "probes": {"database-backup": probes["database-backup"]}
    })


@pytest.mark.parametrize("inherit_pipes", [True, False])
def test_delivery_cleans_up_children_and_retains_pending(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, inherit_pipes: bool
) -> None:
    """A timed-out or asynchronous channel cannot hang or acknowledge delivery."""
    marker = tmp_path / "late-delivery"
    policy = {
        "stateDirectory": str(tmp_path),
        "notificationCommand": [
            sys.executable,
            str(Path(__file__).resolve().parents[1] / "fixtures/process.py"),
            "spawn-delayed",
            str(marker),
            "0.6",
            "2",
            "inherit" if inherit_pipes else "redirect",
        ],
    }
    actual_run = HELPER["run"]

    def bounded(
        arguments: list[str], timeout: int = 30, payload: str | None = None
    ) -> object:
        del timeout
        return actual_run(arguments, timeout=0.1, payload=payload)

    monkeypatch.setitem(HELPER["deliver"].__globals__, "run", bounded)
    deadline_seconds = 2
    started = time.monotonic()
    assert HELPER["deliver"](policy, ["Probe failed"]) == 1
    assert time.monotonic() - started < deadline_seconds
    assert (tmp_path / "delivery/pending.json").exists()
    assert not (tmp_path / "delivery/delivered.json").exists()
    time.sleep(0.7)
    assert not marker.exists()
