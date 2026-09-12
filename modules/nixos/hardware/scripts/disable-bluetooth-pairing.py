"""Disable pairing once each boot-time adapter appears on BlueZ's bus."""

from __future__ import annotations

import argparse
import asyncio
import sys
from builtins import ExceptionGroup

from dbus_next import BusType, Message, MessageType, Variant
from dbus_next.aio import MessageBus

ADAPTER = "org.bluez.Adapter1"
OBJECT_MANAGER = "org.freedesktop.DBus.ObjectManager"
PROPERTIES = "org.freedesktop.DBus.Properties"
DBUS = "org.freedesktop.DBus"


async def call(bus: MessageBus, message: Message) -> Message:
    """Await one D-Bus reply.

    Returns:
        A successful method reply.

    Raises:
        RuntimeError: The service rejected the call or disconnected.

    """
    reply = await bus.call(message)
    if reply is None or reply.message_type != MessageType.METHOD_RETURN:
        reason = reply.error_name if reply is not None else "disconnected"
        raise RuntimeError(reason)
    return reply


async def disable_pairing(adapters: list[str]) -> None:
    """Subscribe before inspecting current adapters, then apply policy once."""
    if not adapters:
        return
    bus = await MessageBus(bus_type=BusType.SYSTEM).connect()
    try:
        owner_reply = await call(
            bus,
            Message(
                destination=DBUS,
                path="/org/freedesktop/DBus",
                interface=DBUS,
                member="GetNameOwner",
                signature="s",
                body=["org.bluez"],
            ),
        )
        owner = owner_reply.body[0]
        ready = {f"/org/bluez/{name}": asyncio.Event() for name in adapters}

        def added(message: Message) -> None:
            if (
                message.message_type == MessageType.SIGNAL
                and message.sender == owner
                and message.interface == OBJECT_MANAGER
                and message.member == "InterfacesAdded"
                and message.signature == "oa{sa{sv}}"
            ):
                path, interfaces = message.body
                if path in ready and ADAPTER in interfaces:
                    ready[path].set()

        bus.add_message_handler(added)
        # Await AddMatch's acknowledgement before taking the snapshot. Events
        # arriving during GetManagedObjects remain recorded in the ready events.
        await call(
            bus,
            Message(
                destination=DBUS,
                path="/org/freedesktop/DBus",
                interface=DBUS,
                member="AddMatch",
                signature="s",
                body=[
                    f"type='signal',sender='{owner}',interface='{OBJECT_MANAGER}',member='InterfacesAdded'"
                ],
            ),
        )
        snapshot = await call(
            bus,
            Message(
                destination=owner,
                path="/",
                interface=OBJECT_MANAGER,
                member="GetManagedObjects",
            ),
        )
        for path, interfaces in snapshot.body[0].items():
            if path in ready and ADAPTER in interfaces:
                ready[path].set()

        async def apply(path: str, event: asyncio.Event) -> None:
            await event.wait()
            await call(
                bus,
                Message(
                    destination=owner,
                    path=path,
                    interface=PROPERTIES,
                    member="Set",
                    signature="ssv",
                    body=[ADAPTER, "Pairable", Variant("b", False)],
                ),
            )

        async with asyncio.TaskGroup() as tasks:
            for path, event in ready.items():
                tasks.create_task(apply(path, event))
    finally:
        bus.disconnect()
        await bus.wait_for_disconnect()


async def main() -> None:
    """Bound the entire operation, including connection and property writes."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--timeout", type=float, default=10, help="overall deadline in seconds"
    )
    parser.add_argument("adapters", nargs="*")
    args = parser.parse_args()
    async with asyncio.timeout(args.timeout):
        await disable_pairing(args.adapters)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except TimeoutError:
        sys.stderr.write(
            "Bluetooth adapters did not become ready for pairing policy before the deadline\n"
        )
        sys.exit(1)
    except (OSError, RuntimeError, ExceptionGroup) as error:
        sys.stderr.write(f"Bluetooth pairing policy failed: {error}\n")
        sys.exit(1)
