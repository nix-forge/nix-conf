"""Require firmware Secure Boot before enrolling hardware-bound disk keys."""

from pathlib import Path

root = Path("/sys/firmware/efi/efivars")
values = list(root.glob("SecureBoot-*"))
if len(values) != 1 or values[0].read_bytes()[4:5] != b"\x01":
    raise SystemExit("Firmware Secure Boot must be enabled before hardware enrollment.")
