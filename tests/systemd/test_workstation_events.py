"""Behavior checks for scheduler telemetry, separate from native resource probes."""

import importlib.util
import json
import os
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Exercise the fixed helper using temporary record roots.
import sys
import tempfile
from pathlib import Path
from unittest.mock import patch

FILE_MODE = 0o600
DIRECTORY_MODE = 0o700
REQUIRED_BYTES = 200
SOURCE = Path(__file__).parents[2] / "homes/desktop/local/workstation_task_events.py"


def test_lifecycle_is_private_monotonic_and_argument_free(tmp_path: Path) -> None:
    """Require private file modes and completed-record filtering."""
    environment = {**os.environ, "XDG_RUNTIME_DIR": str(tmp_path)}
    environment.pop("WORKSTATION_JOB_DIRECTORY", None)
    unit = "workstation-task-feedback-123-456.scope"
    for event in ["queued", "admitted", "commandFinished", "completed"]:
        subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Fixed interpreter/helper and controlled fixture arguments.
            [sys.executable, SOURCE, event, unit, "feedback", "0"],
            check=True,
            env=environment,
        )
    file = tmp_path / "workstation-task-events" / (unit + ".json")
    record = json.loads(file.read_text(encoding="utf-8"))
    assert file.stat().st_mode & 0o777 == FILE_MODE
    assert file.parent.stat().st_mode & 0o777 == DIRECTORY_MODE
    assert record["queueWaitMilliseconds"] >= 0
    assert record["queued"]["monotonicNs"] <= record["completed"]["monotonicNs"]
    assert "command" not in record
    output = subprocess.check_output(  # ruff: ignore[subprocess-without-shell-equals-true] - Fixed helper with status-only arguments.
        [sys.executable, SOURCE, "status"],
        env=environment,
    )
    assert output == b""


def test_invalid_scope_cannot_escape_record_directory(tmp_path: Path) -> None:
    """Reject traversal instead of writing an arbitrary scheduler record."""
    result = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Deliberately invalid fixture identity, without a shell.
        [sys.executable, SOURCE, "queued", "../escape.scope", "feedback"],
        check=False,
        env={**os.environ, "XDG_RUNTIME_DIR": str(tmp_path)},
        capture_output=True,
    )
    assert result.returncode != 0
    assert not (tmp_path / "escape.scope.json").exists()


def test_capacity_refusal_records_the_guard_without_admitting_payload(
    tmp_path: Path,
) -> None:
    """Refused, unreadable and aggregate-limited snapshots remain distinguishable."""
    environment = {**os.environ, "XDG_RUNTIME_DIR": str(tmp_path)}
    environment.pop("WORKSTATION_JOB_DIRECTORY", None)
    cases = [
        (["100", "200", "daemon"], "insufficient-host-memory", 100),
        (["unknown", "200", "daemon"], "unreadable-host-memory", None),
        (
            ["500", "200", "bounded", "90", "20", "100"],
            "insufficient-aggregate-memory",
            500,
        ),
        (["500", "200", "bounded", "80", "20", "100"], "ready", 500),
    ]
    for index, (values, decision, available) in enumerate(cases):
        unit = f"workstation-task-bulk-{index}-1.scope"
        for event, arguments in [
            ("queued", []),
            ("capacityChecked", values),
            ("completed", ["75"]),
        ]:
            subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Fixed helper and capacity fixtures.
                [sys.executable, SOURCE, event, unit, "bulk", *arguments],
                check=True,
                env=environment,
            )
        record = json.loads(
            (tmp_path / "workstation-task-events" / (unit + ".json")).read_text()
        )
        assert "admitted" not in record
        assert record["admission"]["decision"] == decision
        assert record["admission"]["availableBytes"] == available
        assert record["admission"]["requiredBytes"] == REQUIRED_BYTES


def test_optional_psi_cannot_abort_capacity_reporting() -> None:
    """Kernels without PSI still report the real capacity refusal."""
    spec = importlib.util.spec_from_file_location("workstation_task_events", SOURCE)
    assert spec
    assert spec.loader
    events = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(events)
    with patch.object(Path, "read_text", side_effect=OSError("PSI unavailable")):
        snapshot = events.capacity_snapshot(["100", "200", "daemon"])
    assert snapshot["decision"] == "insufficient-host-memory"
    assert snapshot["hostMemoryPressure"] is None


if __name__ == "__main__":
    with tempfile.TemporaryDirectory() as directory:
        test_lifecycle_is_private_monotonic_and_argument_free(Path(directory))
        test_invalid_scope_cannot_escape_record_directory(Path(directory))
    sys.stdout.write("PASS: scheduler telemetry behavior\n")
