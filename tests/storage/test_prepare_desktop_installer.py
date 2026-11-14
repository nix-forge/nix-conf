"""Guard the install-plan generator against unsafe disk selections."""

import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPT = (
    Path(__file__).resolve().parents[2]
    / "hosts/nixos/desktop/local/storage/scripts/prepare_desktop_installer.py"
)
SYSTEM = "/dev/disk/by-id/TEST_SYSTEM_DISK"
DATA = "/dev/disk/by-id/TEST_DATA_DISK"
PRIVATE_DIR_MODE = 0o700
PRIVATE_FILE_MODE = 0o600


@pytest.fixture
def checkout(tmp_path: Path) -> Path:
    """Provide only the tracked files required by the generator.

    Returns:
        A disposable checkout root.

    """
    source = tmp_path / "source"
    for name in (
        "flake.nix",
        "flake.lock",
        "hosts/shared/local/flake/desktop-installer.nix",
        "nix-seal/flake.nix",
        "hosts/nixos/desktop/local/storage/disk-layout.nix",
        "hosts/nixos/desktop/local/storage/deployment.nix",
    ):
        file = source / name
        file.parent.mkdir(parents=True, exist_ok=True)
        file.touch()
    git = shutil.which("git")
    assert git is not None
    subprocess.run([git, "-C", str(source), "init", "-q"], check=True)
    subprocess.run([git, "-C", str(source), "add", "-N", "."], check=True)
    return source


def run_plan(
    checkout: Path, output: Path, system: str, data: str
) -> subprocess.CompletedProcess[str]:
    """Call the public CLI without executing Nix or Disko.

    Returns:
        The completed generator process.

    """
    return subprocess.run(
        [
            sys.executable,
            str(SCRIPT),
            "--system-disk",
            system,
            "--data-disk",
            data,
            "--source",
            str(checkout),
            "--output",
            str(output),
        ],
        check=False,
        capture_output=True,
        text=True,
    )


def test_plan_keeps_disk_ids_private_and_selects_passphrase_boot(
    checkout: Path, tmp_path: Path
) -> None:
    """The generated flake is private and excludes unattended unlock policy."""
    output = tmp_path / "plan"
    result = run_plan(checkout, output, SYSTEM, DATA)
    assert result.returncode == 0, result.stderr
    assert output.stat().st_mode & 0o777 == PRIVATE_DIR_MODE
    assert (output / "flake.nix").stat().st_mode & 0o777 == PRIVATE_FILE_MODE
    plan = (output / "flake.nix").read_text()
    assert f'disko.devices.disk.system.device = lib.mkForce "{SYSTEM}";' in plan
    assert f'disko.devices.disk.data.device = lib.mkForce "{DATA}";' in plan
    assert 'unlockMethod = lib.mkForce "passphrase";' in plan
    assert "hardware.storage.homelabHdd.enable = lib.mkForce false;" in plan


@pytest.mark.parametrize(
    ("system", "data"),
    [
        (SYSTEM, SYSTEM),
        (f"{SYSTEM}-part1", DATA),
        ("/dev/disk/by-id/..", DATA),
        ("/dev/nvme0n1", DATA),
    ],
)
def test_plan_rejects_ambiguous_drives(
    checkout: Path, tmp_path: Path, system: str, data: str
) -> None:
    """Invalid selections fail before creating an output directory."""
    output = tmp_path / "plan"
    result = run_plan(checkout, output, system, data)
    assert result.returncode != 0
    assert not output.exists()


def test_checkout_uri_is_encoded_and_replacements_are_literal(
    checkout: Path, tmp_path: Path
) -> None:
    """A checkout name cannot alter generated Nix or another replacement."""
    checkout = checkout.rename(checkout.with_name("source SYSTEM_DISK # ${literal}"))
    output = tmp_path / "plan"
    result = run_plan(checkout, output, SYSTEM, DATA)
    assert result.returncode == 0, result.stderr
    plan = (output / "flake.nix").read_text()
    uri = json.dumps(f"git+{checkout.as_uri()}?submodules=1")
    assert f"inputs.base.url = {uri};" in plan
    assert "${literal}" not in plan
