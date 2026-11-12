"""Admission and upward-only Linux memory grants, owned by the invoking executor."""

import argparse
import asyncio
import contextlib
import fcntl
import json
import math
import os
import re
import select
import signal
import subprocess  # ruff: ignore[suspicious-subprocess-import] - fixed native manager argv
import sys
from pathlib import Path
from time import monotonic, time

from dbus_next.aio import MessageBus
from dbus_next.constants import BusType
from dbus_next.errors import DBusError

# Native manager calls use explicit argv, never a shell expression.
# ruff: file-ignore[subprocess-without-shell-equals-true]
MIB = 1024**2
PERCENT = 100
UNIT_DISCOVERY_SECONDS = 10
FIRST_LOCK_FD = 3


def invalid(message: str) -> None:
    """Reject a lost allocation invariant.

    Raises:
        ValueError: The allocation cannot safely proceed.

    """
    raise ValueError(message)


def save(path: Path, value: dict) -> None:
    """Durably replace this controller's private allocation receipt."""
    temporary = path.with_suffix(".tmp")
    with temporary.open("w", encoding="utf-8") as stream:
        json.dump(value, stream, sort_keys=True)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    temporary.replace(path)
    descriptor = os.open(path.parent, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def snapshot(meminfo: Path, group: Path | None, root: Path, pressure: Path) -> dict:
    """Read host and all finite ancestor headroom.

    Returns:
        Capacity and pressure observations; missing capacity stays unknown.

    """
    result: dict = {
        "availableBytes": None,
        "ancestorRoomBytes": None,
        "fullPressure": None,
    }
    try:  # ruff: ignore[too-many-statements-in-try-clause] - one conservative snapshot
        match = re.search(
            r"^MemAvailable:\s+(\d+) kB",
            meminfo.read_text(encoding="utf-8"),
            re.MULTILINE,
        )
        if match:
            result["availableBytes"] = int(match[1]) * 1024
        rooms = []
        if group is not None:
            if not group.is_relative_to(root):
                invalid("Memory group must belong to the cgroup root")
            node = group
            while node != root:
                maximum = (node / "memory.max").read_text(encoding="utf-8").strip()
                current = int((node / "memory.current").read_text(encoding="utf-8"))
                if maximum != "max":
                    rooms.append(max(0, int(maximum) - current))
                node = node.parent
        result["ancestorRoomBytes"] = min(rooms) if rooms else None
    except OSError, ValueError:
        result["capacityUnknown"] = True
    try:
        match = re.search(
            r"^full avg10=([\d.]+)", pressure.read_text(encoding="utf-8"), re.MULTILINE
        )
        if match:
            result["fullPressure"] = float(match[1])
    except OSError:
        result["fullPressure"] = None
    return result


def grant(  # ruff: ignore[too-many-arguments, too-many-positional-arguments] - explicit byte-valued selection inputs
    sample: dict,
    minimum: int,
    maximum: int,
    reserve: int,
    quantum: int,
    pressure_limit: float,
    unused: int = 0,
) -> int:
    """Select incremental capacity without spending unused grants twice.

    Returns:
        A viable grant in bytes, or zero while blocked.

    """
    available = sample.get("availableBytes")
    pressure = sample.get("fullPressure")
    if sample.get("capacityUnknown") or available is None:
        return 0
    if pressure is not None and pressure >= pressure_limit:
        return 0
    room = max(0, available - reserve - unused)
    if sample.get("ancestorRoomBytes") is not None:
        room = min(room, max(0, sample["ancestorRoomBytes"] - unused))
    selected = min(maximum, room) // quantum * quantum
    return selected if selected >= minimum else 0


class Notifications:
    """Pressure and cgroup lifecycle hints with a finite recovery timer.

    PSI has no RAM-recovered event and unrelated processes need not change our
    cgroup's population. A positive timer therefore remains necessary.
    """

    def __init__(self, pressure: Path, group: Path | None, root: Path) -> None:
        """Subscribe before the caller samples initial capacity."""
        self.streams = []
        self.poller = select.poll()
        paths = []
        if group is not None and group.is_relative_to(root):
            paths = [
                node / "cgroup.events"
                for node in [group, *group.parents]
                if node.is_relative_to(root)
            ]
        for path in paths:
            try:
                stream = path.open(encoding="utf-8")
                stream.read()
                self.poller.register(stream, select.POLLPRI | select.POLLERR)
                self.streams.append(stream)
            except OSError:
                self.missing_lifecycle_hint = True
        try:
            stream = pressure.open("r+b", buffering=0)
            stream.write(b"full 100000 2000000")
            self.poller.register(stream, select.POLLPRI | select.POLLERR)
            self.streams.append(stream)
        except OSError:
            if "stream" in locals() and stream not in self.streams:
                stream.close()

    def wait(self, seconds: float) -> None:
        """Block on notifications or the recovery timer, acknowledging events."""
        self.poller.poll(max(1, math.ceil(seconds * 1000)))
        for stream in self.streams:
            with contextlib.suppress(OSError):
                stream.seek(0)
                stream.read()

    def close(self) -> None:
        """Release every descriptor owned by this controller."""
        for stream in self.streams:
            stream.close()


def reserve_execution(descriptors: list[int]) -> bool:
    """Try the inherited execution reservations without sleeping on any lock.

    Locks belong to the shell's open file descriptions and survive controller
    exit. Partial acquisition is always released, including mixed-version peers.

    Returns:
        Whether all execution locks are held by the invoking supervisor.

    """
    acquired = []
    try:
        for descriptor in descriptors:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            acquired.append(descriptor)
    except BlockingIOError:
        for descriptor in reversed(acquired):
            fcntl.flock(descriptor, fcntl.LOCK_UN)
        return False
    except BaseException:
        for descriptor in reversed(acquired):
            fcntl.flock(descriptor, fcntl.LOCK_UN)
        raise
    return True


def locked_capacity(
    args: argparse.Namespace, locks: list[int]
) -> tuple[dict | None, int]:
    """Acquire reservations and resample capacity, releasing all on refusal.

    Returns:
        The locked sample and grant, or no sample when another task owns a lock.

    """
    if not reserve_execution(locks):
        return None, 0
    selected = 0
    try:
        sample = snapshot(args.meminfo, args.group, args.root, args.pressure)
        selected = grant(
            sample,
            args.minimum * MIB,
            args.maximum * MIB,
            args.reserve * MIB,
            args.quantum * MIB,
            args.pressure_limit,
        )
        return sample, selected
    finally:
        if not selected:
            for descriptor in reversed(locks):
                fcntl.flock(descriptor, fcntl.LOCK_UN)


def admit(args: argparse.Namespace) -> int:
    """Wait within one deadline and persist a grant before returning it.

    Returns:
        Zero after admission, or 124 after admission expires without launch.

    """
    started = monotonic()
    deadline = started + args.timeout
    healthy = None
    delay = 0.25
    locks = getattr(args, "lock_fd", [])
    reserved = False
    admitted = False
    notices = Notifications(args.pressure, args.group, args.root)
    try:
        while True:
            sample = snapshot(args.meminfo, args.group, args.root, args.pressure)
            selected = grant(
                sample,
                args.minimum * MIB,
                args.maximum * MIB,
                args.reserve * MIB,
                args.quantum * MIB,
                args.pressure_limit,
            )
            now = monotonic()
            healthy = (healthy if healthy is not None else now) if selected else None
            ready = (
                selected > 0
                and healthy is not None
                and now - healthy >= args.healthy_seconds
            )
            waiting_execution = False
            if ready and locks:
                locked_sample, selected = locked_capacity(args, locks)
                waiting_execution = locked_sample is None
                if locked_sample is not None:
                    sample = locked_sample
                ready = selected > 0
                reserved = ready
                if not ready and not waiting_execution:
                    healthy = None
                now = monotonic()
            record = {
                "phase": "admitted" if ready else "waiting-capacity",
                "minimumMiB": args.minimum,
                "maximumMiB": args.maximum,
                "grantMiB": selected // MIB if ready else None,
                "admissionWaitSeconds": now - started,
                "sample": sample,
                "changes": [],
            }
            if waiting_execution:
                record["phase"] = "waiting-execution"
            if now >= deadline:
                record.update(
                    phase="admission-expired", payloadLaunched=False, grantMiB=None
                )
                save(args.receipt, record)
                return 124
            save(args.receipt, record)
            if ready:
                sys.stdout.write(str(selected // MIB) + "\n")
                sys.stdout.flush()
                admitted = True
                return 0
            notices.wait(min(delay, deadline - now))
            delay = min(5, delay * 2)
    finally:
        if reserved and not admitted:
            for descriptor in reversed(locks):
                fcntl.flock(descriptor, fcntl.LOCK_UN)
        notices.close()


async def discover_group(args: argparse.Namespace) -> Path:
    """Subscribe before observing the manager's creation and activation state.

    Returns:
        The owned unit's existing cgroup.

    """
    async with asyncio.timeout(UNIT_DISCOVERY_SECONDS):
        bus = await MessageBus(bus_type=BusType.SESSION).connect()
        try:
            destination = "org.freedesktop.systemd1"
            manager_path = "/org/freedesktop/systemd1"
            description = await bus.introspect(destination, manager_path)
            manager = bus.get_proxy_object(
                destination, manager_path, description
            ).get_interface("org.freedesktop.systemd1.Manager")
            changed = asyncio.Event()

            def unit_new(name: str, _path: str) -> None:
                if name == args.unit:
                    changed.set()

            def job_removed(
                _identifier: int, _path: str, name: str, _result: str
            ) -> None:
                if name == args.unit:
                    changed.set()

            manager.on_unit_new(unit_new)  # ty: ignore[unresolved-attribute] - introspected D-Bus signal
            manager.on_job_removed(job_removed)  # ty: ignore[unresolved-attribute] - introspected D-Bus signal
            await manager.call_subscribe()  # ty: ignore[unresolved-attribute] - introspected D-Bus method
            while True:
                changed.clear()
                response = await asyncio.to_thread(
                    subprocess.run,
                    [
                        args.systemctl,
                        "--user",
                        "show",
                        args.unit,
                        "-p",
                        "ControlGroup",
                        "--value",
                    ],
                    text=True,
                    capture_output=True,
                    check=False,
                    timeout=3,
                )
                value = str(response.stdout).strip()
                if (
                    response.returncode == 0
                    and value.startswith("/")
                    and ".." not in Path(value).parts
                ):
                    group = args.root / value.lstrip("/")
                    if (group / "memory.max").exists():
                        return group
                await changed.wait()
        finally:
            bus.disconnect()
            await bus.wait_for_disconnect()


def grow(args: argparse.Namespace) -> int:  # ruff: ignore[too-many-statements, too-many-locals] - one owned growth lifecycle
    """Increase an owned unit's limits only.

    Returns:
        Zero when growth completes, one when further growth is unsafe.

    """
    record = json.loads(args.receipt.read_text(encoding="utf-8"))
    initial = record["grantMiB"]
    maximum = record["maximumMiB"]
    if initial >= maximum:
        return 0
    try:
        group = asyncio.run(discover_group(args))
    except (OSError, TimeoutError, DBusError) as error:
        record["growthError"] = type(error).__name__
        save(args.receipt, record)
        return 1
    notices = Notifications(args.pressure, group, args.root)
    healthy = None
    try:  # ruff: ignore[too-many-statements-in-try-clause] - preserve pending changes on any update failure
        while initial < maximum:
            current = int((group / "memory.current").read_text(encoding="utf-8"))
            actual = int((group / "memory.max").read_text(encoding="utf-8"))
            # An outside owner changing this unit invalidates our authority.
            if actual != initial * MIB:
                invalid("Owned memory limit changed outside its controller")
            high = int((group / "memory.high").read_text(encoding="utf-8"))
            sample = snapshot(args.meminfo, group.parent, args.root, args.pressure)
            increment = grant(
                sample,
                args.quantum * MIB,
                min(args.step, maximum - initial) * MIB,
                args.reserve * MIB,
                args.quantum * MIB,
                args.pressure_limit - args.pressure_hysteresis,
                max(0, actual - current),
            )
            demand = current >= high * 9 // 10
            record["growthObservation"] = {
                "sample": sample,
                "currentBytes": current,
                "highBytes": high,
                "incrementBytes": increment,
                "demand": demand,
            }
            save(args.receipt, record)
            now = monotonic()
            healthy = (
                (healthy if healthy is not None else now)
                if increment and demand
                else None
            )
            if healthy is not None and now - healthy >= args.growth_seconds:
                target = initial + increment // MIB
                page_size = os.sysconf("SC_PAGE_SIZE")
                high_bytes = (
                    (target * MIB * args.high_percent // 100) // page_size * page_size
                )
                record["pendingGrantMiB"] = target
                save(args.receipt, record)
                subprocess.run(
                    [
                        args.systemctl,
                        "--user",
                        "set-property",
                        "--runtime",
                        args.unit,
                        f"MemoryMax={target * MIB}",
                    ],
                    check=True,
                    capture_output=True,
                    timeout=3,
                )
                subprocess.run(
                    [
                        args.systemctl,
                        "--user",
                        "set-property",
                        "--runtime",
                        args.unit,
                        f"MemoryHigh={high_bytes}",
                    ],
                    check=True,
                    capture_output=True,
                    timeout=3,
                )
                effective = int((group / "memory.max").read_text(encoding="utf-8"))
                if (
                    effective != target * MIB
                    or int((group / "memory.high").read_text(encoding="utf-8"))
                    != high_bytes
                ):
                    invalid("Memory grant readback did not match")
                record["changes"].append({
                    "fromMiB": initial,
                    "toMiB": target,
                    "time": time(),
                    "sample": sample,
                })
                record["grantMiB"] = target
                record.pop("pendingGrantMiB", None)
                save(args.receipt, record)
                initial = target
                healthy = None
            if "populated 0" in (group / "cgroup.events").read_text(encoding="utf-8"):
                break
            notices.wait(2)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        # Retain a possibly applied pending increase; never roll it back.
        record["growthError"] = type(error).__name__
        save(args.receipt, record)
        return 1
    finally:
        notices.close()
    return 0


def main() -> int:
    """Expose controller operations to the owning executor.

    Returns:
        The admission or growth operation's exit status.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["admit", "grow"])
    parser.add_argument("--receipt", type=Path, required=True)
    parser.add_argument("--lock-fd", type=int, action="append", default=[])
    parser.add_argument("--minimum", type=int, default=1)
    parser.add_argument("--maximum", type=int, default=1)
    parser.add_argument("--reserve", type=int, default=0)
    parser.add_argument("--quantum", type=int, default=1)
    parser.add_argument("--timeout", type=float, default=1800)
    parser.add_argument("--healthy-seconds", type=float, default=1)
    parser.add_argument("--pressure-limit", type=float, default=50)
    parser.add_argument("--pressure-hysteresis", type=float, default=5)
    parser.add_argument("--growth-seconds", type=float, default=5)
    parser.add_argument("--step", type=int, default=1024)
    parser.add_argument("--high-percent", type=int, default=90)
    parser.add_argument("--systemctl", default="systemctl")
    parser.add_argument("--unit")
    parser.add_argument("--group", type=Path)
    parser.add_argument("--root", type=Path, default=Path("/sys/fs/cgroup"))
    parser.add_argument("--meminfo", type=Path, default=Path("/proc/meminfo"))
    parser.add_argument("--pressure", type=Path, default=Path("/proc/pressure/memory"))
    args = parser.parse_args()
    if not (
        0 < args.minimum <= args.maximum
        and args.quantum > 0
        and args.reserve >= 0
        and args.timeout > 0
        and args.healthy_seconds >= 0
        and args.growth_seconds > 0
        and 0 < args.pressure_hysteresis < args.pressure_limit <= PERCENT
        and args.step >= args.quantum
        and 0 < args.high_percent < PERCENT
        and all(descriptor >= FIRST_LOCK_FD for descriptor in args.lock_fd)
        and len(set(args.lock_fd)) == len(args.lock_fd)
    ):
        parser.error("Invalid memory allocation policy")
    for number in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(number, lambda signum, _frame: raise_exit(signum))
    return admit(args) if args.action == "admit" else grow(args)


def raise_exit(signum: int) -> None:
    """Make signal cancellation unwind descriptor ownership.

    Raises:
        SystemExit: The owner cancelled this controller.

    """
    raise SystemExit(128 + signum)


if __name__ == "__main__":
    raise SystemExit(main())
