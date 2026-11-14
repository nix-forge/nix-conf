"""Exercise graceful shutdown registration, events, deadline and cleanup."""

from __future__ import annotations

import importlib
import runpy
import sys
from pathlib import Path
from unittest.mock import Mock

import pytest

SCRIPT = (
    Path(__file__).parents[2]
    / "modules/nixos/virtualisation/scripts/libvirt_shutdown.py"
)


class FixtureError(Exception):
    """A libvirt operation failed in the disposable connection."""


@pytest.fixture
def runtime(monkeypatch: pytest.MonkeyPatch) -> tuple[dict, Mock, Mock]:
    """Load the public operation against an event-delivering libvirt fixture.

    Returns:
        The script namespace, mock API and mock domain.

    """
    api = Mock()
    api.libvirtError = FixtureError
    api.VIR_DOMAIN_EVENT_STOPPED = 5
    api.VIR_DOMAIN_EVENT_ID_LIFECYCLE = 0
    api.VIR_DOMAIN_SHUTDOWN_GUEST_AGENT = 2
    api.VIR_DOMAIN_SHUTDOWN_ACPI_POWER_BTN = 1
    domain = api.open.return_value.lookupByName.return_value
    domain.isActive.return_value = True

    def deliver_stop() -> None:
        callback = api.open.return_value.domainEventRegisterAny.call_args.args[2]
        callback(None, domain, api.VIR_DOMAIN_EVENT_STOPPED, 0, None)

    api.virEventRunDefaultImpl.side_effect = deliver_stop
    monkeypatch.setitem(sys.modules, "libvirt", api)
    return runpy.run_path(str(SCRIPT)), api, domain


def test_registration_precedes_snapshot_and_shutdown(runtime: tuple) -> None:
    """The lifecycle subscription exists before any state query or stop request."""
    script, api, domain = runtime

    def snapshot() -> bool:
        api.open.return_value.domainEventRegisterAny.assert_called_once()
        return True

    domain.isActive.side_effect = snapshot
    script["shutdown"]("fixture:///system", "guest", 3)
    domain.isActive.assert_called_once()
    domain.shutdownFlags.assert_called_once_with(api.VIR_DOMAIN_SHUTDOWN_GUEST_AGENT)
    api.virEventRunDefaultImpl.assert_called_once()
    api.virEventRemoveTimeout.assert_called_once()
    api.open.return_value.domainEventDeregisterAny.assert_called_once()
    api.open.return_value.close.assert_called_once()


def test_inactive_guest_needs_no_stop_request(runtime: tuple) -> None:
    """A guest already stopped at the initial snapshot needs no event wait."""
    script, api, domain = runtime
    domain.isActive.return_value = False
    script["shutdown"]("fixture:///system", "guest", 3)
    domain.shutdownFlags.assert_not_called()
    api.virEventRunDefaultImpl.assert_not_called()
    api.open.return_value.close.assert_called_once()


def test_guest_agent_failure_uses_acpi(runtime: tuple) -> None:
    """Agent unavailability falls back to the ordinary graceful ACPI request."""
    script, api, domain = runtime
    domain.shutdownFlags.side_effect = [FixtureError(), None]
    script["shutdown"]("fixture:///system", "guest", 3)
    assert [call.args[0] for call in domain.shutdownFlags.call_args_list] == [
        api.VIR_DOMAIN_SHUTDOWN_GUEST_AGENT,
        api.VIR_DOMAIN_SHUTDOWN_ACPI_POWER_BTN,
    ]


def test_timeout_retains_active_guest(runtime: tuple) -> None:
    """The deadline raises without destroying or changing the guest definition."""
    script, api, domain = runtime

    def expire() -> None:
        callback = api.virEventAddTimeout.call_args.args[1]
        callback(1, None)

    api.virEventRunDefaultImpl.side_effect = expire
    with pytest.raises(TimeoutError):
        script["shutdown"]("fixture:///system", "guest", 3)
    domain.destroy.assert_not_called()
    api.open.return_value.defineXML.assert_not_called()
    api.open.return_value.close.assert_called_once()


def test_failed_requests_propagate(runtime: tuple) -> None:
    """A rejection from both graceful shutdown methods fails immediately."""
    script, api, domain = runtime
    domain.shutdownFlags.side_effect = FixtureError()
    with pytest.raises(FixtureError):
        script["shutdown"]("fixture:///system", "guest", 3)
    api.virEventRunDefaultImpl.assert_not_called()
    api.open.return_value.close.assert_called_once()


def test_stop_during_request_is_observed(runtime: tuple) -> None:
    """A stop between snapshot and request survives until event dispatch."""
    script, api, domain = runtime
    domain.isActive.side_effect = [True, False]
    domain.shutdownFlags.side_effect = FixtureError()
    script["shutdown"]("fixture:///system", "guest", 3)
    api.virEventRunDefaultImpl.assert_called_once()


def test_event_loop_failure_is_not_retried(runtime: tuple) -> None:
    """A failed event loop terminates instead of repeatedly calling the broken API."""
    script, api, _domain = runtime
    api.virEventRunDefaultImpl.side_effect = FixtureError()
    with pytest.raises(FixtureError):
        script["shutdown"]("fixture:///system", "guest", 3)
    api.virEventRunDefaultImpl.assert_called_once()
    api.open.return_value.close.assert_called_once()


@pytest.mark.skipif(
    sys.platform != "linux", reason="NixOS lifecycle helper uses libvirt"
)
def test_native_lifecycle_delivery(monkeypatch: pytest.MonkeyPatch) -> None:
    """Dispatch a real lifecycle event through libvirt's disposable test driver."""
    api = importlib.import_module("libvirt")
    # The test driver accepts only its default shutdown method. Exercise real
    # registration and dispatch while adapting QEMU-specific request flags.
    monkeypatch.setattr(
        api.virDomain, "shutdownFlags", lambda domain, _flags: domain.shutdown()
    )
    script = runpy.run_path(str(SCRIPT))
    script["shutdown"]("test:///default", "test", 3)
