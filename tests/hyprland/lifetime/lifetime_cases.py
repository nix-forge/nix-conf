"""Hold the original service pidfd through every probe and manager completion."""

from __future__ import annotations

import argparse
import asyncio
import json
import os
from pathlib import Path
from time import monotonic
from typing import TYPE_CHECKING

from notification_process import run

if TYPE_CHECKING:
    from collections.abc import Awaitable, Callable

    from dbus_next import Message, MessageType

SCENARIOS = ("orphan", "disconnect", "feedback", "child-first")
UNIT_NAME = "lifetime-compositor.service"
CLEANUP_TIMEOUT = 5
UNIT_PATH = "/org/freedesktop/systemd1/unit/lifetime_2dcompositor_2eservice"


async def wait_finished(
    read_state: Callable[[], Awaitable[dict]],
    changed: asyncio.Event,
    deadline: float,
) -> dict:
    """Subscribe before snapshots and reread only on manager notifications.

    Returns:
        Final inactive or failed unit properties.

    Raises:
        TimeoutError: The shared manager completion deadline expires.

    """
    while True:
        changed.clear()
        remaining = deadline - monotonic()
        if remaining <= 0:
            message = "Manager completion exceeded the shutdown deadline"
            raise TimeoutError(message)
        state = await asyncio.wait_for(read_state(), remaining)
        if state["ActiveState"] in {"inactive", "failed"}:
            return state
        remaining = deadline - monotonic()
        if remaining <= 0:
            message = "Manager completion exceeded the shutdown deadline"
            raise TimeoutError(message)
        await asyncio.wait_for(changed.wait(), remaining)


def subscribe_exit(loop: asyncio.AbstractEventLoop, descriptor: int) -> asyncio.Future:
    """Remove a level-triggered pidfd reader after its first exit notification.

    Returns:
        A future fulfilled by the original process exit notification.

    """
    dead = loop.create_future()

    def process_exited() -> None:
        loop.remove_reader(descriptor)
        if not dead.done():
            dead.set_result(None)

    loop.add_reader(descriptor, process_exited)
    return dead


class UnitObserver:
    """Keep the original process descriptor and manager reference under one owner."""

    def __init__(self, message: type[Message], message_type: type[MessageType]) -> None:
        """Create ownership state before acquiring any descriptor or bus connection."""
        self.message = message
        self.message_type = message_type
        self.bus = None
        self.connected = False
        self.descriptor = None
        self.loop = asyncio.get_running_loop()
        self.dead = None
        self.handler_added = False
        self.reference_attempted = False
        self.changed = asyncio.Event()

    def properties_changed(self, message: Message) -> None:
        """Wake the snapshot reader only for the owned unit property signal."""
        if (
            message.message_type == self.message_type.SIGNAL
            and message.path == UNIT_PATH
            and message.interface == "org.freedesktop.DBus.Properties"
            and message.member == "PropertiesChanged"
        ):
            self.changed.set()

    async def properties(self, interface: str) -> dict:
        """Read the requested interface from the explicitly referenced unit.

        Returns:
            Native properties with their D-Bus variant values unwrapped.

        """
        assert self.bus is not None
        reply = await self.bus.call(
            self.message(
                destination="org.freedesktop.systemd1",
                path=UNIT_PATH,
                interface="org.freedesktop.DBus.Properties",
                member="GetAll",
                signature="s",
                body=[interface],
            )
        )
        assert reply is not None, reply
        assert reply.message_type == self.message_type.METHOD_RETURN, reply
        return {name: variant.value for name, variant in reply.body[0].items()}

    async def unit_state(self) -> dict:
        """Read manager lifecycle properties.

        Returns:
            The current unit state supplied by the manager.

        """
        return await self.properties("org.freedesktop.systemd1.Unit")

    async def reference(self, member: str) -> None:
        """Acquire or release exactly the owned manager unit reference."""
        assert self.bus is not None
        reply = await self.bus.call(
            self.message(
                destination="org.freedesktop.systemd1",
                path="/org/freedesktop/systemd1",
                interface="org.freedesktop.systemd1.Manager",
                member=member,
                signature="s",
                body=[UNIT_NAME],
            )
        )
        assert reply is not None, reply
        assert reply.message_type == self.message_type.METHOD_RETURN, reply

    async def acquire(self, pid: int) -> None:
        """Hold the manager reference and subscribe before checking the live PID."""
        assert self.bus is not None
        await self.bus.connect()
        self.connected = True
        self.reference_attempted = True
        await self.reference("RefUnit")
        self.descriptor = os.pidfd_open(pid)
        self.dead = subscribe_exit(self.loop, self.descriptor)
        self.handler_added = True
        self.bus.add_message_handler(self.properties_changed)
        subscription = await self.bus.call(
            self.message(
                destination="org.freedesktop.DBus",
                path="/org/freedesktop/DBus",
                interface="org.freedesktop.DBus",
                member="AddMatch",
                signature="s",
                body=[
                    "type='signal',sender='org.freedesktop.systemd1',"
                    "interface='org.freedesktop.DBus.Properties',"
                    "member='PropertiesChanged',path='" + UNIT_PATH + "'"
                ],
            )
        )
        assert subscription is not None, subscription
        assert subscription.message_type == self.message_type.METHOD_RETURN, (
            subscription
        )
        subscribed = await self.bus.call(
            self.message(
                destination="org.freedesktop.systemd1",
                path="/org/freedesktop/systemd1",
                interface="org.freedesktop.systemd1.Manager",
                member="Subscribe",
            )
        )
        assert subscribed is not None, subscribed
        assert subscribed.message_type == self.message_type.METHOD_RETURN, subscribed
        service = await self.properties("org.freedesktop.systemd1.Service")
        assert service["MainPID"] == pid, service
        assert (await self.unit_state())["ActiveState"] == "active"

    async def cleanup(self) -> None:
        """Release descriptors and references before closing the owned bus."""
        # Teardown has a separate budget, not a new completion deadline.
        deadline = monotonic() + CLEANUP_TIMEOUT
        try:
            if self.descriptor is not None:
                try:
                    self.loop.remove_reader(self.descriptor)
                finally:
                    os.close(self.descriptor)
            if self.bus is not None and self.reference_attempted:
                # An interrupted RefUnit reply may still have acquired a ref.
                await asyncio.wait_for(
                    self.reference("UnrefUnit"), max(0, deadline - monotonic())
                )
        finally:
            if self.bus is not None:
                await self.close_bus(deadline)

    def close_transport(self) -> None:
        """Remove owned readers before closing both transport handles."""
        assert self.bus is not None
        try:
            self.bus._finalize()  # ruff: ignore[private-member-access] -- Pinned dbus-next requires this EOF-reader finalizer after failed authentication.
        finally:
            try:
                self.bus._stream.close()  # ruff: ignore[private-member-access] -- disconnect only shuts down the socket; close its owned stream.
            finally:
                self.bus._sock.close()  # ruff: ignore[private-member-access] -- Close the same owned socket even after stream-close failure.

    async def close_bus(self, deadline: float) -> None:
        """Bound disconnection while preserving early-failure transport cleanup."""
        assert self.bus is not None
        try:
            if self.handler_added:
                self.bus.remove_message_handler(self.properties_changed)
        finally:
            try:
                self.bus.disconnect()
                if not self.connected:
                    self.bus._finalize()  # ruff: ignore[private-member-access] -- Pinned dbus-next installs its EOF reader only after authentication.
                await asyncio.wait_for(
                    self.bus.wait_for_disconnect(), max(0, deadline - monotonic())
                )
            finally:
                self.close_transport()


def run_cases(*, child_first_control: bool) -> tuple[list, int | None]:
    """Run the original native client and liveness checks in their original order.

    Returns:
        Ordered successful cases and the first real client or liveness failure.

    """
    results = []
    failure = None
    scenarios = ("child-first",) if child_first_control else SCENARIOS
    iterations = 1 if child_first_control else 5
    for scenario in scenarios:
        for iteration in range(iterations):
            probe = run(
                ["lifetime-client", scenario],
                capture_output=True,
                text=True,
                timeout=10,
            )
            print(  # ruff: ignore[print] -- Bounded per-case native diagnostics retained by the VM owner.
                f"{scenario} iteration {iteration}: status={probe.returncode}\n{probe.stdout}{probe.stderr}",
                flush=True,
            )
            if probe.returncode != 0:
                failure = probe.returncode
                break
            status = run(
                ["hyprctl", "version"], capture_output=True, text=True, timeout=2
            )
            if status.returncode != 0:
                failure = status.returncode
                break
            results.append([scenario, iteration, 0])
        if failure is not None:
            break
    return results, failure


async def exercise(
    pid: int, signature: str, *, expect_crash: bool, child_first_control: bool = False
) -> dict:
    """Require actual probes, original process death, and manager final properties.

    Returns:
        Actual probe results and manager-confirmed exit metadata.

    Raises:
        TimeoutError: Completion or cleanup exceeds its original bound.
        asyncio.CancelledError: Cancellation is re-raised after owned cleanup.

    """
    from dbus_next import BusType, Message, MessageType  # ruff: ignore[import-outside-top-level] -- VM transport is loaded after fixture injection.
    from dbus_next.aio import MessageBus  # ruff: ignore[import-outside-top-level] -- Same transport seam for acquisition-failure fixtures.

    owner = UnitObserver(Message, MessageType)
    try:
        owner.bus = MessageBus(bus_type=BusType.SYSTEM)
        await owner.acquire(pid)
        assert not (expect_crash and child_first_control)
        results, failure = run_cases(child_first_control=child_first_control)
        deadline = monotonic() + 10
        if expect_crash:
            assert failure is not None, "Raw package unexpectedly survived all cases"
        else:
            assert failure is None, results
            assert len(results) == (1 if child_first_control else 20), results
            run(
                ["hyprctl", "-i", signature, "dispatch", "hl.dsp.exit()"],
                check=True,
                capture_output=True,
                timeout=2,
            )
        remaining = deadline - monotonic()
        if remaining <= 0:
            message = "Exit dispatch exceeded the shutdown deadline"
            raise TimeoutError(message)
        assert owner.dead is not None
        await asyncio.wait_for(asyncio.shield(owner.dead), remaining)
        await wait_finished(owner.unit_state, owner.changed, deadline)
        final = await asyncio.wait_for(
            owner.properties("org.freedesktop.systemd1.Service"),
            max(0, deadline - monotonic()),
        )
        assert final["MainPID"] == 0, final
        shutdown = {
            "status": final["ExecMainStatus"],
            "code": final["ExecMainCode"],
            "result": final["Result"],
        }
        return {
            "results": results,
            "baselineFailure": failure,
            "shutdown": shutdown,
            "originalPidfdExitObserved": True,
            "managerCompletionObserved": True,
        }
    finally:
        pending = asyncio.create_task(owner.cleanup())
        cancelled = False
        while True:
            try:
                await asyncio.shield(pending)
                break
            except asyncio.CancelledError:
                if pending.cancelled():
                    raise
                cancelled = True
        if cancelled:
            raise asyncio.CancelledError


def main() -> None:
    """Write the actual native lifecycle receipt for the owning VM driver."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pid", type=int)
    parser.add_argument("signature")
    parser.add_argument("--expect-crash", action="store_true")
    parser.add_argument("--child-first-control", action="store_true")
    args = parser.parse_args()
    receipt = asyncio.run(
        exercise(
            args.pid,
            args.signature,
            expect_crash=args.expect_crash,
            child_first_control=args.child_first_control,
        )
    )
    with Path("/tmp/lifetime-proof/cases.json").open("w", encoding="utf-8") as output:  # ruff: ignore[hardcoded-temp-file] -- Fresh isolated guest-owned evidence directory.
        json.dump(receipt, output)


if __name__ == "__main__":
    main()
