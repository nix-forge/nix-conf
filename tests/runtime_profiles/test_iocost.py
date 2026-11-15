"""Exercise adaptive controller writes against kernel-format fixture files."""

from __future__ import annotations

import shlex
import shutil
import subprocess  # ruff: ignore[suspicious-subprocess-import]
from pathlib import Path

import pytest

INVALID_DEVICE_STATUS = 2
SOURCE = Path(__file__).parents[2] / "modules/nixos/hardware/iocost-assets/enable.sh"


def invoke(tmp_path: Path, device: str = "259:0") -> subprocess.CompletedProcess[str]:
    """Run the real controller helper with an isolated cgroup root.

    Returns:
        Exit status and captured output from the real script.

    """
    script = SOURCE.read_text().replace("@cgroupRoot@", shlex.quote(str(tmp_path)))
    return subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true]
        [str(shutil.which("bash")), "-c", script, "enable-iocost", device],
        check=False,
        capture_output=True,
        text=True,
    )


def test_adaptive_policy(tmp_path: Path) -> None:
    """A supported unmeasured disk receives both native controller settings."""
    model = tmp_path / "io.cost.model"
    qos = tmp_path / "io.cost.qos"
    model.touch()
    qos.touch()
    assert invoke(tmp_path).returncode == 0
    assert model.read_text() == "259:0 ctrl=auto\n"
    assert qos.read_text() == "259:0 enable=1 ctrl=auto\n"


@pytest.mark.parametrize("policy", ["io.cost.model", "io.cost.qos"])
def test_preserve_measured_policy(tmp_path: Path, policy: str) -> None:
    """Either file can mark an operator policy that must remain untouched."""
    for name in ["io.cost.model", "io.cost.qos"]:
        (tmp_path / name).write_text("259:1 ctrl=auto\n")
    (tmp_path / policy).write_text("259:0 ctrl=user rbps=123456\n")
    before = {p.name: p.read_bytes() for p in tmp_path.iterdir()}
    assert invoke(tmp_path).returncode == 0
    assert {p.name: p.read_bytes() for p in tmp_path.iterdir()} == before


def test_unavailable_controller_and_invalid_device(tmp_path: Path) -> None:
    """Missing kernel support fails clearly without creating controller files."""
    assert invoke(tmp_path).returncode == 1
    assert invoke(tmp_path, "259:0 injected").returncode == INVALID_DEVICE_STATUS
    assert list(tmp_path.iterdir()) == []


def test_reconciliation_preserves_hwdb_and_selects_only_requested_disks(
    tmp_path: Path,
) -> None:
    """Skip measured hwdb disks while reconciling only selected whole disks."""
    assets = SOURCE.parent
    block = tmp_path / "block"
    for name, number in [("nvme0n1", "259:0"), ("nvme1n1", "259:1"), ("sda", "8:0")]:
        directory = block / name
        directory.mkdir(parents=True)
        (directory / "dev").write_text(number, encoding="utf-8")
    calls = tmp_path / "calls"
    enable = tmp_path / "enable"
    enable.write_text(
        "#!"
        + str(shutil.which("bash"))
        + "\nprintf '%s\\n' \"$1\" >> "
        + shlex.quote(str(calls)),
        encoding="utf-8",
    )
    enable.chmod(0o700)
    script = (
        (assets / "reconcile.sh")
        .read_text()
        .replace("@patterns@", shlex.quote("nvme*n*"))
        .replace("/sys/block/*", shlex.quote(str(block)) + "/*")
        .replace("@enable@", shlex.quote(str(enable)))
    )
    # The fake native metadata provider marks only one selected disk measured.
    provider = """udevadm() {
        if [[ ${*: -1} == *nvme0n1 ]]; then
            printf 'IOCOST_SOLUTIONS=measured\\n'
        else
            printf 'IOCOST_SOLUTIONS=\\n'
        fi
    }
    """
    result = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true]
        [str(shutil.which("bash")), "-c", provider + script],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    assert calls.read_text(encoding="utf-8") == "259:1\n"
