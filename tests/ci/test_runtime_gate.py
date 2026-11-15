"""Exercise the hosted CI graph and native proof's real shell consumer."""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[2]
JOBS = yaml.safe_load((ROOT / ".github/workflows/ci.yml").read_text())["jobs"]


@pytest.mark.parametrize("result", ["success", "failure", "cancelled", "skipped"])
def test_static_result_controls_native_and_required_aggregate(
    tmp_path: Path, result: str
) -> None:
    """A failed gate blocks native jobs and cannot become a green required check."""
    for name in ["flake", "native"] + [
        key for key in JOBS if key.endswith("review-proof")
    ]:
        job = JOBS[name]
        assert "static" in job["needs"]
        condition = job.get("if", "")
        # GitHub applies success() implicitly unless a status function appears.
        if "!cancelled()" in condition:
            assert "needs.static.result == 'success'" in condition
        else:
            assert "always()" not in condition
    aggregate = JOBS["tests"]
    assert "static" in aggregate["needs"]
    step = aggregate["steps"][0]
    assert step["env"]["STATIC_RESULT"] == "${{ needs.static.result }}"
    outcome = subprocess.run(
        ["bash", "-e", "-c", step["run"]],
        env=os.environ
        | {
            "STATIC_RESULT": result,
            "FLAKE_RESULT": "success",
            "SUBMODULE_RESULT": "success",
            "GUIDE_CHANGED": "false",
            "GUIDE_RESULT": "skipped",
            "NATIVE_RESULT": "skipped",
        },
        cwd=tmp_path,
        check=False,
    )
    assert (outcome.returncode == 0) == (result == "success")


@pytest.mark.parametrize("fail_phase", ["", "artifact", "shell", "native"])
def test_handy_realizes_each_input_once_and_always_runs_host_proof(
    tmp_path: Path, fail_phase: str
) -> None:
    """Execute the workflow step, preserving failures and exact realized inputs."""
    tools = tmp_path / "bin"
    tools.mkdir()
    fixture = ROOT / "tests/ci/fixtures/handy-command.sh"
    for name in ("nix", "python3"):
        shutil.copyfile(fixture, tools / name)
        (tools / name).chmod(0o755)
    step = next(
        step
        for step in JOBS["flake"]["steps"]
        if "Handy microphone" in step.get("name", "")
    )
    assert step["if"] == "matrix.system == 'aarch64-darwin'"
    steps = JOBS["flake"]["steps"]
    process = next(
        s for s in steps if s.get("name") == "Verify native Darwin process supervision"
    )
    matrix = next(
        s for s in steps if s.get("name") == "Build assigned native CI checks"
    )
    assert steps.index(step) < steps.index(process) < steps.index(matrix)
    assert "nix develop" not in process["run"]
    result = subprocess.run(
        ["bash", "-e", "-c", step["run"] + "\n" + process["run"]],
        cwd=ROOT,
        env=os.environ
        | {
            "RUNNER_TEMP": str(tmp_path),
            "PATH": str(tools) + os.pathsep + os.environ["PATH"],
            "FAIL_PHASE": fail_phase,
        },
        capture_output=True,
        text=True,
        check=False,
    )
    calls = (tmp_path / "calls").read_text().splitlines()
    assert calls.count("artifact") == 1
    if fail_phase != "artifact":
        assert calls.count("shell") == 1
    if fail_phase not in {"artifact", "shell"}:
        assert calls.count("native") == 1
        if not fail_phase:
            assert calls.count("native-process") == 1
        assert "Handy native identity and signature execution" in result.stdout
    assert (result.returncode == 0) == (not fail_phase)


def test_static_has_one_ci_execution_owner() -> None:
    """The hosted inventory and hook consumer defer Python work to the gate."""
    gate = JOBS["static"]
    assert any(
        step.get("run")
        == "nix build --no-link --print-build-logs .#checks.x86_64-linux.python-quality"
        for step in gate["steps"]
    )
    lint = JOBS["lint"]
    assert "static" in lint["needs"]
    hooks = next(
        step for step in lint["steps"] if "/repository-checks@" in step.get("uses", "")
    )
    assert set(hooks["env"]["SKIP"].split(",")) == {
        "ruff",
        "ruff-format",
        "ty",
        "python-compile",
    }
    assert any(
        step.get("with", {}).get("checks-output") == "hostedLintChecks"
        for step in lint["steps"]
    )
