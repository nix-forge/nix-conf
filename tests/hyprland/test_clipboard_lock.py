"""Exercise clipboard lock cleanup over a private logind notification bus."""

from __future__ import annotations

# D-Bus decorators use protocol names and signatures rather than Python types.
# ruff: file-ignore[invalid-function-name, quoted-annotation, undefined-name, forward-annotation-syntax-error, no-self-use, docstring-missing-returns]
import asyncio
import json
import os
import runpy
import sys
from pathlib import Path

import pytest
from dbus_next import Message
from dbus_next.aio import MessageBus
from dbus_next.constants import PropertyAccess
from dbus_next.service import ServiceInterface, dbus_property, method, signal

pytest_plugins = ["dbus_helpers"]
MODULE = runpy.run_path(
    str(Path(__file__).parents[2] / "modules/home/desktop/scripts/clipboard_lock.py")
)
LOGIN = MODULE["LOGIN"]
ROOT = MODULE["ROOT"]
SESSION = MODULE["SESSION"]


class Session(ServiceInterface):
    """Publish owner and lock state using logind's public interface."""

    def __init__(self, uid: int, *, locked: bool = False) -> None:
        """Declare a session with explicit owner and lock state."""
        super().__init__(SESSION)
        self.uid = uid
        self.locked = locked

    @dbus_property(access=PropertyAccess.READ)
    def User(self) -> "(uo)":  # ty: ignore[unresolved-reference] - D-Bus signature.
        """Return the logind owner tuple."""
        return [self.uid, ROOT + "/user/test"]

    @dbus_property(access=PropertyAccess.READ)
    def LockedHint(self) -> "b":  # ty: ignore[unresolved-reference] - D-Bus signature.
        """Expose the current lock state."""
        return self.locked

    @signal()
    def Lock(self) -> "":  # ty: ignore[invalid-syntax-in-forward-annotation] - Empty D-Bus signature.
        """Emit a lock request."""
        return None


class Manager(ServiceInterface):
    """Expose the initial session snapshot."""

    @method()
    def ListSessions(self) -> "a(susso)":  # ty: ignore[invalid-type-form] - D-Bus signature.
        """Return the one existing user session."""
        return [["own", os.getuid(), "tester", "", ROOT + "/session/own"]]


async def exercise(address: str, temporary: Path) -> None:
    """Check initial state, ownership filtering and subsequent lock signals."""
    received: asyncio.Queue[bytes] = asyncio.Queue()

    async def receive(
        reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        received.put_nowait(await reader.read())
        writer.close()
        await writer.wait_closed()

    # macOS UNIX sockets have a short path limit; use the private temporary root.
    socket_path = temporary / "wipe.sock"
    server = await asyncio.start_unix_server(receive, path=str(socket_path))
    command = temporary / "cliphist"
    command.write_text(
        f"#!{sys.executable}\nimport socket\ns=socket.socket(socket.AF_UNIX)\n"
        f"s.connect({json.dumps(str(socket_path))})\ns.sendall(b'wipe')\ns.close()\n"
    )
    command.chmod(0o755)
    bus = await MessageBus(bus_address=address).connect()
    own = Session(os.getuid(), locked=True)
    foreign = Session(os.getuid() + 1)
    bus.export(ROOT, Manager(LOGIN + ".Manager"))
    bus.export(ROOT + "/session/own", own)
    bus.export(ROOT + "/session/foreign", foreign)
    await bus.request_name(LOGIN)
    client = await MessageBus(bus_address=address).connect()
    listener = MODULE["LockMonitor"](client, str(command))
    client.add_message_handler(listener.notification)
    task: asyncio.Task[None] | None = None
    try:
        await listener.subscribe()
        assert await received.get() == b"wipe"
        task = asyncio.create_task(listener.consume())
        own.locked = False
        foreign.Lock()
        own.Lock()
        assert await received.get() == b"wipe"
        # The listener processes the two preceding signals sequentially.
        assert received.empty()
        own.emit_properties_changed({"LockedHint": True})
        assert await received.get() == b"wipe"
        # A directed signal from another owner must not enter the lock queue.
        listener.notification(
            Message(
                sender=":1.spoof",
                path=ROOT + "/session/own",
                interface=SESSION,
                member="Lock",
                message_type=MODULE["MessageType"].SIGNAL,
            )
        )
        assert listener.events.empty()
    finally:
        if task is not None:
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)
        client.disconnect()
        bus.disconnect()
        server.close()
        await server.wait_closed()


def test_user_lock_cleanup(private_bus: str, tmp_path: Path) -> None:
    """Wipe current and future user locks without touching other users."""
    asyncio.run(asyncio.wait_for(exercise(private_bus, tmp_path), timeout=10))


async def exercise_stuck_wipe(address: str, temporary: Path, cancel: bool) -> None:
    """Kill and reap a TERM-ignoring child on cancellation or timeout."""
    received: asyncio.Queue[bytes] = asyncio.Queue()

    async def receive(
        reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        received.put_nowait(await reader.read())
        writer.close()
        await writer.wait_closed()

    socket_path = temporary / "stuck.sock"
    server = await asyncio.start_unix_server(receive, path=str(socket_path))
    command = temporary / "stuck-cliphist"
    command.write_text(
        f"#!{sys.executable}\nimport os, signal, socket\n"
        "signal.signal(signal.SIGTERM, signal.SIG_IGN)\n"
        "s=socket.socket(socket.AF_UNIX)\n"
        f"s.connect({json.dumps(str(socket_path))})\ns.sendall(str(os.getpid()).encode())\ns.close()\n"
        "while True: signal.pause()\n",
        encoding="utf-8",
    )
    command.chmod(0o755)
    bus = await MessageBus(bus_address=address).connect()
    listener = MODULE["LockMonitor"](
        bus,
        str(command),
        wipe_timeout_seconds=1,
        terminate_grace_seconds=0.1,
    )
    task = asyncio.create_task(listener.wipe())
    try:
        pid = int(await received.get())
        if cancel:
            task.cancel()
        with pytest.raises(asyncio.CancelledError if cancel else TimeoutError):
            await task
        with pytest.raises(ProcessLookupError):
            os.kill(pid, 0)
    finally:
        task.cancel()
        await asyncio.gather(task, return_exceptions=True)
        bus.disconnect()
        server.close()
        await server.wait_closed()


@pytest.mark.parametrize("cancel", [True, False])
def test_stuck_wipe_is_reaped(private_bus: str, tmp_path: Path, cancel: bool) -> None:
    """Bound failed cleanup so notification processing and shutdown can recover."""
    asyncio.run(
        asyncio.wait_for(exercise_stuck_wipe(private_bus, tmp_path, cancel), timeout=5)
    )
