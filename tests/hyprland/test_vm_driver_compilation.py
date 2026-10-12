"""Validate the embedded driver in NixOS's prepended type-checking context."""

from pathlib import Path


def test_nixos_can_prepend_guest_type_definitions() -> None:
    """Compile the actual driver after guest definitions, before building its VMs."""
    driver = Path(__file__).with_name("subsurface_parent_lifetime_vm.py")
    preamble = "from typing import Any\nbaseline: Any\nrepaired: Any\n"
    compile(preamble + driver.read_text(), str(driver), "exec", dont_inherit=True)
