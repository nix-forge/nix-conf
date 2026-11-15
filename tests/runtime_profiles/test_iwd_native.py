"""Exercise profile installation against IWD's actual native keyfile parser."""

from __future__ import annotations

import os
import shutil
from typing import TYPE_CHECKING

import pytest
from notification_process import run

if TYPE_CHECKING:
    import subprocess
    from pathlib import Path

pytestmark = pytest.mark.nix_integration


def _install(
    source: Path, state: Path, profile_type: str
) -> subprocess.CompletedProcess[bytes]:
    return run(
        [
            os.environ["IWD_MATERIALIZER"],
            str(source),
            str(state),
            os.environ["IWD_VALIDATOR"],
            profile_type,
        ],
        capture_output=True,
    )


def test_embedded_pem_and_native_grammar(tmp_path: Path) -> None:
    """Accept embedded certificates and resume the previous native group."""
    certificate = tmp_path / "certificate.pem"
    run(
        [
            str(shutil.which("openssl")),
            "req",
            "-x509",
            "-newkey",
            "rsa:2048",
            "-nodes",
            "-days",
            "1",
            "-subj",
            "/CN=fixture.example.test",
            "-keyout",
            str(tmp_path / "key.pem"),
            "-out",
            str(certificate),
        ],
        check=True,
        capture_output=True,
    )
    body = (
        b"[Security]\nEAP-Method=TLS\nEAP-TLS-CACert=embed:fixture\n"
        b"[@pem@fixture]\n"
        + certificate.read_bytes()
        + b"EAP-Identity=fixture\n[Settings]\nAutoConnect=false\n"
        b"[Settings]\nAutoConnect=true\nKey.With.Dot=value\n"
    )
    source = tmp_path / "source"
    source.write_bytes(b"SSID=Enterprise\n" + body)
    source.chmod(0o600)
    result = _install(source, tmp_path / "state", "8021x")
    assert result.returncode == 0, result.stderr
    assert (tmp_path / "state" / "Enterprise.8021x").read_bytes() == body
    assert result.stdout == result.stderr == b""


@pytest.mark.parametrize(
    "body",
    [
        b"Security\nPassphrase=invalid",
        b"[Security]\nPassphrase: invalid",
        b"[Security]\n[@pem@fixture]\n-----BEGIN CERTIFICATE-----\nmissing end\n",
    ],
)
def test_native_rejection_retains_working_profile(tmp_path: Path, body: bytes) -> None:
    """Native syntax errors leave the working file and inode intact."""
    source = tmp_path / "source"
    original = b"[Security]\nPassphrase=fixture-password\n"
    source.write_bytes(b"SSID=Example\n" + original)
    source.chmod(0o600)
    state = tmp_path / "state"
    assert _install(source, state, "psk").returncode == 0
    destination = state / "Example.psk"
    inode = destination.stat().st_ino
    source.write_bytes(b"SSID=Example\n" + body)
    result = _install(source, state, "psk")
    assert result.returncode == 1
    assert destination.read_bytes() == original
    assert destination.stat().st_ino == inode
    assert b"fixture-password" not in result.stderr
