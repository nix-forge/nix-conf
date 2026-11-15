"""Ensure exempt shells cannot manufacture GUI acceptance evidence."""

from __future__ import annotations

import importlib.util
import socket
from pathlib import Path
from types import SimpleNamespace

import pytest

SPEC = importlib.util.spec_from_file_location(
    "application_network_test",
    Path(__file__).parents[2] / "modules/home/macos/application_network_test.py",
)
assert SPEC
assert SPEC.loader
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)


def test_ssh_origin_is_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    """Reject a process chain that ends in sshd."""
    monkeypatch.setattr(
        probe, "run", lambda _: SimpleNamespace(returncode=0, stdout="1 /usr/sbin/sshd")
    )
    with pytest.raises(ValueError, match="SSH/Terminal"):
        probe.ancestry(Path("/Applications/ChatGPT.app"))


def test_gui_origin_has_exact_canonical_path(monkeypatch: pytest.MonkeyPatch) -> None:
    """Retain the real GUI ancestor instead of matching an app basename."""
    monkeypatch.setattr(
        probe,
        "run",
        lambda _: SimpleNamespace(
            returncode=0, stdout="1 /Applications/ChatGPT.app/Contents/MacOS/ChatGPT"
        ),
    )
    assert (
        probe.ancestry(Path("/Applications/ChatGPT.app"))[0]["executable"]
        == "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT"
    )
    with pytest.raises(ValueError, match="canonical"):
        probe.ancestry(Path("/Other/ChatGPT.app"))


def test_loopback_is_not_a_permission_test(monkeypatch: pytest.MonkeyPatch) -> None:
    """Reject an exempt loopback endpoint before issuing a probe."""
    monkeypatch.setattr(probe, "ancestry", lambda _: [])
    args = SimpleNamespace(
        app=Path("/Applications/ChatGPT.app"), endpoint=["127.0.0.1:22"]
    )
    with pytest.raises(ValueError, match="loopback"):
        probe.acceptance(args)


def test_dns_answers_are_pinned_once(monkeypatch: pytest.MonkeyPatch) -> None:
    """Retain numeric destinations even if a later hostname lookup would change."""
    calls = []

    def lookup(host: str, port: int, **_kwargs: object) -> list:
        """Return a LAN answer once and an exempt loopback answer afterward.

        Returns:
            A simulated resolver answer.

        """
        calls.append(host)
        address = "192.168.50.10" if len(calls) == 1 else "127.0.0.1"
        return [(socket.AF_INET, socket.SOCK_STREAM, 6, "", (address, port))]

    monkeypatch.setattr(probe.socket, "getaddrinfo", lookup)
    assert probe.resolve_endpoints(["service.test:22"]) == [
        ("service.test", "192.168.50.10", 22)
    ]
    assert calls == ["service.test"]
