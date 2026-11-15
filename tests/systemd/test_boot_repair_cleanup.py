"""Retire only owned scoped repairs, preserving foreign unit overrides."""

import shutil
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Fixed local shell fixture.
from pathlib import Path

import pytest

ROOT = Path(__file__).parents[2]


@pytest.mark.parametrize("repair", ["boot", "dnssec"])
@pytest.mark.parametrize("state", ["owned", "foreign", "regular", "missing"])
def test_retire_only_owned_repair(tmp_path: Path, state: str, repair: str) -> None:
    """A changed or absent override must retain both its content and the root."""
    source = ROOT / (
        "hosts/nixos/desktop/local/scripts/retire-boot-repair.sh"
        if repair == "boot"
        else "hosts/nixos/desktop/local/network/scripts/retire-dnssec-preview.sh"
    )
    assert source.is_file(), (
        f"Production cleanup script missing from test source: {source}"
    )
    root = tmp_path / "gc-root"
    owned = root / "mkswap-swap-workstation.service" if repair == "boot" else root
    root.symlink_to(tmp_path / "unavailable-store-path")
    override = tmp_path / "unit"
    if state in {"owned", "foreign"}:
        override.symlink_to(owned if state == "owned" else tmp_path / "foreign-unit")
    elif state == "regular":
        override.write_text("foreign unit\n")
    bash = shutil.which("bash")
    assert bash is not None
    result = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Literal fixture arguments, no shell expansion.
        [bash, str(source), str(override), str(root)],
        check=False,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr
    assert root.is_symlink() == (state != "owned")
    assert override.is_symlink() == (state == "foreign")
    if state == "regular":
        assert override.read_text() == "foreign unit\n"
