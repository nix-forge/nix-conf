"""Observe a confined workload OOM through systemd property notifications."""

import asyncio
import os
import sys
from pathlib import Path
from typing import Any

from dbus_next import BusType, Message, MessageType
from dbus_next.aio import MessageBus

DESTINATION = "org.freedesktop.systemd1"
MANAGER = "/org/freedesktop/systemd1"


async def main() -> None:
    """Subscribe before triggering allocation, and retain terminal OOM evidence."""
    directory, unit = sys.argv[1:]
    root = Path(directory)
    ready = root / "oom-ready"
    release = root / "oom-release"
    survivor = root / "incorrect-survivor"
    os.mkfifo(ready)
    os.mkfifo(release)
    release_fd = os.open(release, os.O_RDWR | os.O_CLOEXEC)
    fd = os.open(ready, os.O_RDWR | os.O_NONBLOCK | os.O_CLOEXEC)
    loop = asyncio.get_running_loop()
    readiness = loop.create_future()

    def notified() -> None:
        if not readiness.done():
            readiness.set_result(os.read(fd, 256))
        loop.remove_reader(fd)

    loop.add_reader(fd, notified)
    bus = await MessageBus(bus_type=BusType.SESSION).connect()
    job = None
    changed = asyncio.Event()

    async def call(
        path: str,
        interface: str,
        member: str,
        signature: str = "",
        body: list[Any] | None = None,
    ) -> list[Any]:
        response = await bus.call(
            Message(
                destination=DESTINATION,
                path=path,
                interface=interface,
                member=member,
                signature=signature,
                body=body or [],
            )
        )
        assert response is not None
        assert response.message_type != MessageType.ERROR, response
        return response.body

    try:
        job = await asyncio.create_subprocess_exec(
            "systemd-run",
            "--user",
            "--scope",
            "--quiet",
            f"--unit={unit}",
            "--slice=background-workload.slice",
            "-p",
            "OOMPolicy=kill",
            "-p",
            "MemoryMax=96M",
            "-p",
            "MemorySwapMax=0",
            sys.executable,
            str(Path(__file__).with_name("workstation_task_child.py")),
            "oom-parent",
            str(ready),
            str(release),
            str(survivor),
        )
        await asyncio.wait_for(readiness, 10)
        await call(MANAGER, "org.freedesktop.systemd1.Manager", "Subscribe")
        path = (
            await call(
                MANAGER, "org.freedesktop.systemd1.Manager", "GetUnit", "s", [unit]
            )
        )[0]

        def signal(message: Message) -> None:
            if message.path == path and message.member == "PropertiesChanged":
                changed.set()

        bus.add_message_handler(signal)
        response = await bus.call(
            Message(
                destination="org.freedesktop.DBus",
                path="/org/freedesktop/DBus",
                interface="org.freedesktop.DBus",
                member="AddMatch",
                signature="s",
                body=[
                    f"type='signal',sender='{DESTINATION}',path='{path}',interface='org.freedesktop.DBus.Properties'"
                ],
            )
        )
        assert response is not None
        assert response.message_type != MessageType.ERROR
        # Initial snapshot follows subscription. The fixture cannot allocate yet.
        await call(
            path,
            "org.freedesktop.DBus.Properties",
            "Get",
            "ss",
            ["org.freedesktop.systemd1.Scope", "Result"],
        )
        os.write(release_fd, b"allocate\n")
        async with asyncio.timeout(10):
            while True:
                changed.clear()
                result = (
                    await call(
                        path,
                        "org.freedesktop.DBus.Properties",
                        "Get",
                        "ss",
                        ["org.freedesktop.systemd1.Scope", "Result"],
                    )
                )[0].value
                if result == "oom-kill":
                    break
                await changed.wait()
            assert await job.wait() != 0, "expected confined workload OOM"
        assert not survivor.exists(), "OOM left a partial task alive"
    finally:
        loop.remove_reader(fd)
        os.close(fd)
        os.close(release_fd)
        bus.disconnect()
        if job is not None and job.returncode is None:
            job.terminate()
            try:
                await asyncio.wait_for(job.wait(), 10)
            except TimeoutError:
                job.kill()
                await job.wait()


if __name__ == "__main__":
    asyncio.run(main())
