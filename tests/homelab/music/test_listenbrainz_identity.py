"""Validate ownership before the vanilla Aurral link can mutate an account."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import stat
from pathlib import Path
from typing import TYPE_CHECKING

import pytest

if TYPE_CHECKING:
    from types import ModuleType

SCRIPT = (
    Path(__file__).resolve().parents[3]
    / "hosts/nixos/desktop/local/homelab/music/scripts/verify_listenbrainz_identity.py"
)


def load_verifier() -> ModuleType:
    """Load the exact service helper without running its command.

    Returns:
        The operational verifier module.

    """
    spec = importlib.util.spec_from_file_location(
        "listenbrainz_identity_fixture", SCRIPT
    )
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.mark.parametrize(
    "response", [{"valid": False}, {"valid": True, "user_name": "other"}, {}]
)
def test_mismatched_owner_removes_stale_receipt(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path, response: dict[str, object]
) -> None:
    """A changed or invalid token cannot reuse a previously accepted identity."""
    module = load_verifier()
    credentials = tmp_path / "identity.json"
    credentials.write_text(
        json.dumps({"listenbrainzUsername": "listener", "token": "fixture-secret"})
    )
    receipt = tmp_path / "receipt.json"
    receipt.write_text("stale")

    def provider(token: str) -> tuple[bool, str]:
        assert token == "fixture-secret"
        return response.get("valid") is True, str(response.get("user_name", ""))

    monkeypatch.setattr(module, "token_identity", provider)
    with pytest.raises(RuntimeError, match="owner"):
        module.verify(credentials, receipt)
    assert not receipt.exists()


def test_matching_identity_receipt_is_private_and_contains_no_token(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    """The bootstrap receives only an exact fingerprint of a verified account."""
    module = load_verifier()
    credentials = tmp_path / "identity.json"
    credentials.write_text(
        json.dumps({"listenbrainzUsername": "listener", "token": "fixture-secret"})
    )
    receipt = tmp_path / "receipt.json"

    def provider(token: str) -> tuple[bool, str]:
        assert token == "fixture-secret"
        return True, "listener"

    monkeypatch.setattr(module, "token_identity", provider)
    module.verify(credentials, receipt)
    assert json.loads(receipt.read_text()) == {
        "username": "listener",
        "fingerprint": hashlib.sha256(b"listener\0fixture-secret").hexdigest(),
    }
    assert "fixture-secret" not in receipt.read_text()
    assert stat.S_IMODE(receipt.stat().st_mode) == stat.S_IRUSR


def test_history_only_identity_does_not_contact_provider(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    """Public listening history remains usable without a scrobbling token."""
    module = load_verifier()
    credentials = tmp_path / "identity.json"
    credentials.write_text(json.dumps({"listenbrainzUsername": "listener"}))
    receipt = tmp_path / "receipt.json"

    def unexpected(token: str) -> None:
        assert token
        message = "history-only profiles must not send a token"
        raise AssertionError(message)

    monkeypatch.setattr(module, "token_identity", unexpected)
    module.verify(credentials, receipt)
    assert not receipt.exists()
