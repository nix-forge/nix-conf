"""Exercise private IWD profile provisioning with native filename rules."""

from __future__ import annotations

import os
import runpy
import stat
from functools import partial
from pathlib import Path

import pytest

MODULE = runpy.run_path(
    str(
        Path(__file__).parents[2]
        / "modules/nixos/network/iwd-profiles-assets/materialize_profile.py"
    )
)
# These portable cases exercise protected file lifecycle and SSID handling.
# The Linux iwd-runtime-profiles check exercises the real native parser.
MATERIALIZE = partial(MODULE["materialize"], validator=lambda _body: None)
PRIVATE_FILE_MODE = 0o600
PRIVATE_DIRECTORY_MODE = 0o700
BODY = b"[Security]\nPassphrase=fixture-password\n[Settings]\nAutoConnect=true\n"


@pytest.mark.parametrize(
    "ssid", ["Example Network", "example.with.dot", "a/b", "=network", "café"]
)
def test_profile_filename_and_permissions(tmp_path: Path, ssid: str) -> None:
    """Preserve private data while using IWD's literal or encoded SSID name."""
    source = tmp_path / "source"
    source.write_bytes(b"SSID=" + ssid.encode() + b"\n" + BODY)
    source.chmod(0o600)
    state = tmp_path / "state"
    destination = MATERIALIZE(source, state, "psk")
    name = ssid if ssid == "Example Network" else "=" + ssid.encode().hex()
    assert destination.name == name + ".psk"
    assert destination.read_bytes() == BODY
    assert stat.S_IMODE(destination.stat().st_mode) == PRIVATE_FILE_MODE
    assert stat.S_IMODE(state.stat().st_mode) == PRIVATE_DIRECTORY_MODE
    original = destination.stat().st_ino
    assert MATERIALIZE(source, state, "psk").stat().st_ino == original


@pytest.mark.parametrize(
    "header",
    [
        b"SSID=",
        b"SSID=" + b"a" * 33,
        b"SSID=bad\x00name",
        b"SSID=\xff",
        b"OTHER=network",
    ],
)
def test_invalid_source_retains_profile(tmp_path: Path, header: bytes) -> None:
    """Malformed supplied input cannot replace the last working profile."""
    source = tmp_path / "source"
    state = tmp_path / "state"
    source.write_bytes(b"SSID=Example\n" + BODY)
    source.chmod(0o600)
    destination = MATERIALIZE(source, state, "psk")
    source.write_bytes(header + b"\n" + BODY)
    with pytest.raises((ValueError, UnicodeError)):
        MATERIALIZE(source, state, "psk")
    assert destination.read_bytes() == BODY


def test_rejects_public_source_and_replaces_destination_link(tmp_path: Path) -> None:
    """Do not follow a mutable target link or accept readable credentials."""
    source = tmp_path / "source"
    source.write_bytes(b"SSID=Example\n" + BODY)
    source.chmod(0o644)
    with pytest.raises(ValueError, match="private"):
        MATERIALIZE(source, tmp_path / "state", "psk")
    source.chmod(0o600)
    destination = MATERIALIZE(source, tmp_path / "state", "psk")
    external = tmp_path / "external"
    external.write_bytes(b"must remain unchanged")
    destination.unlink()
    destination.symlink_to(external)
    MATERIALIZE(source, tmp_path / "state", "psk")
    assert not destination.is_symlink()
    assert external.read_bytes() == b"must remain unchanged"


def test_root_or_user_owned_runtime_link(tmp_path: Path) -> None:
    """Resolve provider-managed links without exposing runtime content."""
    source = tmp_path / "generation" / "source"
    source.parent.mkdir()
    source.write_bytes(b"SSID=Example\n" + BODY)
    source.chmod(0o600)
    link = tmp_path / "current"
    link.symlink_to(source)
    result = MATERIALIZE(link, tmp_path / "state", "psk")
    assert result.read_bytes() == BODY
    assert result.stat().st_uid == os.getuid()
