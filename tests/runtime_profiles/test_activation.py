"""Exercise activation hostname checks without depending on the test host."""

from __future__ import annotations

import os
import shlex
import shutil
import subprocess  # ruff: ignore[suspicious-subprocess-import]
from pathlib import Path

import pytest

SCRIPT = (
    Path(__file__).parents[2]
    / "modules/nixos/system/activation-safety-assets/check-hostname.sh"
)


@pytest.mark.parametrize(
    ("actual", "booted", "override", "expected_status"),
    [
        ("target", True, "", 0),
        ("other", True, "", 1),
        ("other", True, "target", 0),
        ("other", True, "wrong", 1),
        ("installer", False, "", 0),
    ],
)
def test_hostname_gate(
    tmp_path: Path, actual: str, *, booted: bool, override: str, expected_status: int
) -> None:
    """Block an unintended host switch while permitting explicit migration."""
    hostname = tmp_path / "hostname"
    hostname.write_text(actual, encoding="utf-8")
    booted_system = tmp_path / "booted"
    if booted:
        booted_system.mkdir()
    script = (
        SCRIPT
        .read_text()
        .replace("/proc/sys/kernel/hostname", shlex.quote(str(hostname)))
        .replace("/run/booted-system", shlex.quote(str(booted_system)))
        .replace("@expectedHostname@", shlex.quote("target"))
    )
    result = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true]
        [str(shutil.which("bash")), "-c", script],
        env={**os.environ, "EXPECTED_HOSTNAME": override},
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == expected_status, result.stderr


@pytest.mark.parametrize(
    ("active", "candidate", "expected_status"),
    [
        (None, "", 0),
        (None, "private-desktop", 0),
        ("private-desktop", "private-desktop", 0),
        ("private-desktop", "", 1),
        ("private-desktop", "other", 1),
        ("", "", 1),
    ],
)
def test_deployment_identity_gate(
    tmp_path: Path, active: str | None, candidate: str, expected_status: int
) -> None:
    """A public build cannot silently omit the active private deployment."""
    identity = tmp_path / "deployment-id"
    if active is not None:
        identity.write_text(active)
    script = (
        SCRIPT
        .with_name("check-deployment-identity.sh")
        .read_text()
        .replace(
            "/run/current-system/etc/nixos/deployment-id", shlex.quote(str(identity))
        )
        .replace("@deploymentIdentity@", shlex.quote(candidate))
    )
    result = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true]
        [str(shutil.which("bash")), "-c", script],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == expected_status, result.stderr
