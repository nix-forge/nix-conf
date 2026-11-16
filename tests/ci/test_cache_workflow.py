"""Exercise trusted static-cache consumers and the real producer command boundary."""

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).parents[2]
USAGE_ERROR = 2


def workflow(name: str) -> dict:
    """Read the actual workflow preserving GitHub's on key as text.

    Returns:
        The workflow mapping with string-valued YAML scalars.

    """
    return yaml.load(
        (ROOT / ".github/workflows" / name).read_text(), Loader=yaml.BaseLoader
    )


def test_static_consumers_never_request_writes_and_match_seed_workloads() -> None:
    """PR consumers are read-only and share the two reviewed producer identities."""
    ci = workflow("ci.yml")
    seed = workflow("ci-cache.yml")
    producer = seed["jobs"]["seed"]
    assert "github.event.repository.default_branch" in producer["if"]
    assert set(seed["on"]) == {"push", "workflow_dispatch"}
    assert producer["permissions"] == {"contents": "read"}
    assert seed["permissions"] == {}
    scopes = {entry["scope"] for entry in producer["strategy"]["matrix"]["include"]}
    assert scopes == {"ci-python", "ci-lint"}
    for job in [ci["jobs"]["static"], ci["jobs"]["lint"]]:
        setup = next(
            step
            for step in job["steps"]
            if "/actions/setup-nix@" in step.get("uses", "")
        )
        assert setup["with"]["cache"] == "true"
        assert setup["with"]["cache-write-mode"] == "read-only"
        assert setup["with"]["cache-scope"] in scopes
    setup = next(
        step
        for step in producer["steps"]
        if "/actions/setup-nix@" in step.get("uses", "")
    )
    assert setup["with"]["cache-write-mode"] == "seed"


@pytest.mark.parametrize("shell", ["ciPython", "ci", "unexpected"])
def test_real_seed_command_retains_only_reviewed_tool_profiles(
    tmp_path: Path, shell: str
) -> None:
    """Real shell flow realizes once, retains its profile and refuses other targets."""
    tools = tmp_path / "bin"
    tools.mkdir()
    record = tmp_path / "calls.jsonl"
    command = tools / "nix"
    fixture = (ROOT / "tests/ci/fixtures/cache_command.py").read_text(encoding="utf-8")
    command.write_text(f"#!{sys.executable}\n" + fixture, encoding="utf-8")
    command.chmod(0o700)
    summary = tmp_path / "summary.md"
    result = subprocess.run(
        ["bash", str(ROOT / ".github/scripts/seed-ci-cache.sh")],
        env=os.environ
        | {
            "PATH": str(tools) + os.pathsep + os.environ["PATH"],
            "DEV_SHELL": shell,
            "RUNNER_TEMP": str(tmp_path),
            "CACHE_SCOPE": "test",
            "GITHUB_STEP_SUMMARY": str(summary),
            "CACHE_TEST_RECORD": str(record),
        },
        check=False,
        capture_output=True,
        text=True,
    )
    if shell == "unexpected":
        assert result.returncode == USAGE_ERROR
        assert not record.exists()
        return
    assert result.returncode == 0, result.stderr
    calls = [json.loads(line) for line in record.read_text().splitlines()]
    assert calls == [
        [
            "print-dev-env",
            ".#" + shell,
            "--profile",
            str(tmp_path / "cache-environment"),
        ],
        ["path-info", "--closure-size", str(tmp_path / "cache-environment")],
    ]
    assert "export FIXTURE=1" in (tmp_path / "cache-environment.sh").read_text()
    assert "1234" in summary.read_text()


@pytest.mark.nix_daemon
def test_effective_ci_cache_configuration_preserves_default_and_reviewed_providers() -> (
    None
):
    """Feed the real workflow-owned configuration to Nix, without trusting a flake."""
    config = workflow("ci.yml")["env"]["NIX_CONFIG"]
    assert "accept-flake-config" not in config
    executable = shutil.which("nix")
    assert executable
    settings = json.loads(
        subprocess.check_output(
            [executable, "config", "show", "--json"],
            env=os.environ | {"NIX_CONFIG": config},
            text=True,
        )
    )
    source = (ROOT / "flake.nix").read_text()
    expected = re.search(r"extra-substituters\s*=\s*\[(.*?)\];", source, re.DOTALL)
    assert expected
    providers = re.findall(r'"([^"\n]+)"', expected[1])
    effective = {value.rstrip("/") for value in settings["substituters"]["value"]}
    assert {"https://cache.nixos.org"} <= effective
    assert set(providers) <= effective
    keys = re.search(r"extra-trusted-public-keys\s*=\s*\[(.*?)\];", source, re.DOTALL)
    assert keys
    expected_keys = re.findall(r'"([^"\n]+)"', keys[1])
    assert set(expected_keys) <= set(settings["trusted-public-keys"]["value"])
