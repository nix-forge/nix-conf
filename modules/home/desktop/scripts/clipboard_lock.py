"""Clear clipboard history on the current user's logind lock notifications."""

from __future__ import annotations

import argparse
import asyncio
import contextlib
import os

from dbus_next import BusType, Message, MessageType
from dbus_next.aio import MessageBus

LOGIN = "org.freedesktop.login1"
ROOT = "/org/freedesktop/login1"
SESSION = LOGIN + ".Session"
DBUS = "org.freedesktop.DBus"
PROPERTIES = DBUS + ".Properties"


async def call(bus: MessageBus, message: Message) -> Message:
    """Call a bus method or report the service's failure.

    Returns:
        The successful method reply.

    Raises:
        RuntimeError: The service rejected the method call.

    """
    async with asyncio.timeout(10):
        reply = await bus.call(message)
    if reply is None:
        detail = "logind method call returned no reply"
        raise RuntimeError(detail)
    if reply.message_type == MessageType.ERROR:
        detail = f"{reply.error_name}: {reply.body}"
        raise RuntimeError(detail)
    return reply


class LockMonitor:
    """Own subscriptions, session snapshots and sequential history cleanup."""

    def __init__(
        self,
        bus: MessageBus,
        cliphist: str,
        *,
        wipe_timeout_seconds: float = 10,
        terminate_grace_seconds: float = 2,
    ) -> None:
        """Keep the connected bus and cleanup command with the listener."""
        self.bus = bus
        self.cliphist = cliphist
        self.wipe_timeout_seconds = wipe_timeout_seconds
        self.terminate_grace_seconds = terminate_grace_seconds
        self.login_owner = ""
        self.events: asyncio.Queue[tuple[str, bool]] = asyncio.Queue()

    def notification(self, message: Message) -> None:
        """Accept session signals only from logind's verified bus owner."""
        if message.message_type != MessageType.SIGNAL:
            return
        if (
            message.sender == DBUS
            and message.interface == DBUS
            and message.member == "NameOwnerChanged"
            and message.body[0] == LOGIN
        ):
            self.events.put_nowait(("", False))
            return
        if message.sender != self.login_owner:
            return
        locked = message.interface == SESSION and message.member == "Lock"
        changed = (
            message.interface == PROPERTIES
            and message.member == "PropertiesChanged"
            and message.body[0] == SESSION
            and "LockedHint" in message.body[1]
            and message.body[1]["LockedHint"].value
        )
        if locked or changed:
            self.events.put_nowait((message.path, True))
        elif message.interface == LOGIN + ".Manager" and message.member == "SessionNew":
            self.events.put_nowait((message.body[1], False))

    async def inspect(self, path: str, lock_requested: bool) -> None:
        """Clear history for a lock belonging to this user.

        Raises:
            RuntimeError: Session inspection or clipboard cleanup failed.

        """
        async with asyncio.timeout(10):
            reply = await self.bus.call(
                Message(
                    destination=LOGIN,
                    path=path,
                    interface=PROPERTIES,
                    member="GetAll",
                    signature="s",
                    body=[SESSION],
                )
            )
        if reply is None:
            detail = "logind session inspection returned no reply"
            raise RuntimeError(detail)
        if reply.message_type == MessageType.ERROR:
            # A session can disappear between its notification and inspection.
            if reply.error_name in {
                LOGIN + ".NoSuchSession",
                DBUS + ".Error.UnknownObject",
            }:
                return
            detail = f"{reply.error_name}: {reply.body}"
            raise RuntimeError(detail)
        properties = reply.body[0]
        if properties["User"].value[0] != os.getuid():
            return
        if lock_requested or properties["LockedHint"].value:
            await self.wipe()

    async def wipe(self) -> None:
        """Bound cleanup execution and reap the child on timeout or cancellation.

        Execution and cleanup deadlines propagate TimeoutError to the supervisor.

        Raises:
            RuntimeError: The clipboard command failed.

        """
        process = await asyncio.create_subprocess_exec(self.cliphist, "wipe")
        try:
            async with asyncio.timeout(self.wipe_timeout_seconds):
                status = await process.wait()
        finally:
            if process.returncode is None:
                with contextlib.suppress(ProcessLookupError):
                    process.terminate()
                try:
                    async with asyncio.timeout(self.terminate_grace_seconds):
                        await process.wait()
                except TimeoutError:
                    with contextlib.suppress(ProcessLookupError):
                        process.kill()
                    async with asyncio.timeout(self.terminate_grace_seconds):
                        await process.wait()
        if status:
            detail = f"Clipboard history wipe failed with status {status}"
            raise RuntimeError(detail)

    async def subscribe(self) -> None:
        """Subscribe before reading the owner and initial session snapshot."""
        rules = [
            f"type='signal',sender='{DBUS}',interface='{DBUS}',member='NameOwnerChanged',arg0='{LOGIN}'",
            f"interface='{SESSION}',member='Lock'",
            f"interface='{PROPERTIES}',member='PropertiesChanged',arg0='{SESSION}'",
            f"interface='{LOGIN}.Manager',member='SessionNew'",
        ]
        for index, rule in enumerate(rules):
            if index:
                match = f"type='signal',sender='{LOGIN}',path_namespace='{ROOT}',{rule}"
            else:
                match = rule
            await call(
                self.bus,
                Message(
                    destination=DBUS,
                    path="/org/freedesktop/DBus",
                    interface=DBUS,
                    member="AddMatch",
                    signature="s",
                    body=[match],
                ),
            )
            if index == 0:
                owner = await call(
                    self.bus,
                    Message(
                        destination=DBUS,
                        path="/org/freedesktop/DBus",
                        interface=DBUS,
                        member="GetNameOwner",
                        signature="s",
                        body=[LOGIN],
                    ),
                )
                self.login_owner = owner.body[0]
        sessions = await call(
            self.bus,
            Message(
                destination=LOGIN,
                path=ROOT,
                interface=LOGIN + ".Manager",
                member="ListSessions",
            ),
        )
        for _name, uid, _user, _seat, path in sessions.body[0]:
            if uid == os.getuid():
                await self.inspect(path, False)

    async def consume(self) -> None:
        """Wait for lock events or disconnects without polling.

        Raises:
            RuntimeError: The bus disconnected or logind changed its owner.

        """
        disconnected = asyncio.create_task(self.bus.wait_for_disconnect())
        try:
            while True:
                event = asyncio.create_task(self.events.get())
                try:
                    done, _pending = await asyncio.wait(
                        [event, disconnected],
                        return_when=asyncio.FIRST_COMPLETED,
                    )
                    if disconnected in done:
                        detail = "logind notification bus disconnected"
                        raise RuntimeError(detail)
                    path, requested = event.result()
                    if not path:
                        detail = "logind owner changed; reconnecting for a new snapshot"
                        raise RuntimeError(detail)
                    await self.inspect(path, requested)
                finally:
                    event.cancel()
                    await asyncio.gather(event, return_exceptions=True)
        finally:
            disconnected.cancel()
            await asyncio.gather(disconnected, return_exceptions=True)


async def monitor(cliphist: str, *, bus_address: str | None = None) -> None:
    """Run the listener, keeping connection cleanup with its owner."""
    connection = (
        MessageBus(bus_type=BusType.SYSTEM)
        if bus_address is None
        else MessageBus(bus_address=bus_address)
    )
    bus = await connection.connect()
    listener = LockMonitor(bus, cliphist)
    bus.add_message_handler(listener.notification)
    try:
        await listener.subscribe()
        await listener.consume()
    finally:
        bus.disconnect()


def main() -> None:
    """Run the listener with the package selected by its owning module."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cliphist")
    arguments = parser.parse_args()
    asyncio.run(monitor(arguments.cliphist))


if __name__ == "__main__":
    main()
