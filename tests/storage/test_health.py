"""Check service freshness and delivery acknowledgement without a desktop session."""

from __future__ import annotations

import json
import runpy
import sys
import time
from pathlib import Path
from typing import TYPE_CHECKING

import pytest

if TYPE_CHECKING:
    from typing import Any

HELPER = runpy.run_path(
    str(Path(__file__).parents[2] / "hosts/nixos/desktop/local/storage/health.py")
)


def test_delivery_retries_failure_and_reports_recovery(tmp_path: Path) -> None:
    """Failed delivery must retry; successful warnings and recovery deduplicate."""
    log = tmp_path / "events"
    policy = {
        "stateDirectory": str(tmp_path),
        "notificationCommand": [sys.executable, "-c", "raise SystemExit(1)"],
    }
    assert HELPER["deliver"](policy, ["Probe failed"]) == 1
    assert (tmp_path / "delivery/pending.json").exists()
    assert not (tmp_path / "delivery/delivered.json").exists()
    policy["notificationCommand"] = [
        sys.executable,
        "-c",
        f"import pathlib,sys; p=pathlib.Path({str(log)!r}); p.open('a').write(sys.stdin.read())",
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
    """An absent channel cannot silently acknowledge warnings."""
    policy = {"stateDirectory": str(tmp_path), "notificationCommand": None}
    assert HELPER["deliver"](policy, ["Missing backup"]) == 1
    assert (
        json.loads((tmp_path / "delivery/pending.json").read_text())["event"]
        == "warning"
    )
    policy["notificationCommand"] = [sys.executable, "-c", "pass"]
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
                "-c",
                "print('private-token'); raise SystemExit(1)",
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
    child = f"import pathlib,time; time.sleep(0.6); pathlib.Path({str(marker)!r}).touch(); time.sleep(2)"
    output = (
        ""
        if inherit_pipes
        else ", stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL"
    )
    hook = f"import subprocess,sys; subprocess.Popen([sys.executable, '-c', {child!r}]{output})"
    policy = {
        "stateDirectory": str(tmp_path),
        "notificationCommand": [sys.executable, "-c", hook],
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
