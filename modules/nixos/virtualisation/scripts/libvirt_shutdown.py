"""Request graceful guest shutdown and wait on registered lifecycle events."""

from __future__ import annotations

import argparse
from typing import Any

import libvirt

# libvirt's callback ABI supplies connection, domain, event detail and opaque data.
# ruff: file-ignore[any-type]


def _request_shutdown(domain: Any) -> None:
    """Prefer the guest agent, falling back to ACPI if it is unavailable.

    Raises:
        libvirt.libvirtError: Both requests failed while the guest remains active.

    """
    try:
        domain.shutdownFlags(libvirt.VIR_DOMAIN_SHUTDOWN_GUEST_AGENT)
    except libvirt.libvirtError:
        try:
            domain.shutdownFlags(libvirt.VIR_DOMAIN_SHUTDOWN_ACPI_POWER_BTN)
        except libvirt.libvirtError:
            if domain.isActive():
                raise


def shutdown(uri: str, name: str, timeout: int) -> None:
    """Subscribe before requesting shutdown, retaining the guest on timeout.

    Raises:
        ValueError: The timeout is not positive.
        TimeoutError: The guest did not stop within the deadline.

    """
    if timeout <= 0:
        message = "Shutdown timeout must be positive"
        raise ValueError(message)
    libvirt.virEventRegisterDefaultImpl()
    connection = libvirt.open(uri)
    subscription = None
    timer = None
    stopped = False
    expired = False

    def lifecycle(
        _connection: Any, _domain: Any, event: int, _detail: int, _opaque: Any
    ) -> None:
        nonlocal stopped
        if event == libvirt.VIR_DOMAIN_EVENT_STOPPED:
            stopped = True

    def deadline(_timer: int, _opaque: Any) -> None:
        nonlocal expired
        expired = True

    try:
        domain = connection.lookupByName(name)
        subscription = connection.domainEventRegisterAny(
            domain, libvirt.VIR_DOMAIN_EVENT_ID_LIFECYCLE, lifecycle, None
        )
        timer = libvirt.virEventAddTimeout(timeout * 1000, deadline, None)
        # The initial snapshot follows registration, so a concurrent stop cannot
        # disappear between querying state and subscribing to its notification.
        if not domain.isActive():
            return
        _request_shutdown(domain)
        while not stopped and not expired:
            libvirt.virEventRunDefaultImpl()
        if not stopped:
            message = "Guest did not stop before the shutdown deadline"
            raise TimeoutError(message)
    finally:
        if timer is not None:
            libvirt.virEventRemoveTimeout(timer)
        if subscription is not None:
            connection.domainEventDeregisterAny(subscription)
        connection.close()


def main() -> None:
    """Parse a guest and connection, then wait for graceful shutdown."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("uri")
    parser.add_argument("guest")
    parser.add_argument("--timeout", type=int, default=300)
    args = parser.parse_args()
    shutdown(args.uri, args.guest, args.timeout)


if __name__ == "__main__":
    main()
