"""Bound normalization work while preserving case-insensitive privacy matching."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import pytest

SCRIPT = (
    Path(__file__).resolve().parents[2] / "modules/home/dev/scripts/git-privacy-hook.py"
)
SPEC = importlib.util.spec_from_file_location("privacy_inspection", SCRIPT)
assert SPEC is not None
assert SPEC.loader is not None
privacy = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(privacy)


class CountedBytes(bytes):
    """Measure full-buffer normalization at the scanner's input boundary."""

    lower_calls = 0

    def lower(self) -> bytes:
        """Count the full-buffer copy.

        Returns:
            The normalized bytes.

        """
        self.lower_calls += 1
        return super().lower()


@pytest.mark.parametrize("address_count", [1, 20])
@pytest.mark.parametrize("separator", [None, "@", "\\@", "%40", "&#64;", "&#x40;"])
def test_normalization_is_independent_of_policy_size(
    tmp_path: Path, address_count: int, separator: str | None
) -> None:
    """Scan once per chunk and still reject every mixed-case address encoding."""
    policy = tmp_path / "policy.json"
    policy.write_text(
        json.dumps({
            "blockedEmails": [f"user{i}@example.invalid" for i in range(address_count)]
        }),
        encoding="utf-8",
    )
    policy.chmod(0o600)
    guard = privacy.Guard("unused-git", "unused-gh", policy)
    payload = b"CLEAN DATA " * 100_000
    if separator is not None:
        payload += f"UsEr{address_count - 1}{separator}EXAMPLE.INVALID".encode()
    data = CountedBytes(payload)
    if separator is None:
        guard.inspect(data)
    else:
        with pytest.raises(privacy.PrivacyError, match="Blocked private email"):
            guard.inspect(data)
    assert data.lower_calls == 1
