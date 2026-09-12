"""Exercise adapter notifications and policy writes over a private D-Bus bus."""

from __future__ import annotations

# The private-bus fixture owns message ordering, deadlines, and child cleanup.
# ruff: file-ignore[complex-structure, too-many-statements]
import asyncio
import os
import shutil
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Private bus and policy processes only.
import sys
from pathlib import Path
from typing import TYPE_CHECKING

import pytest
from dbus_next import Message, MessageType, Variant
from dbus_next.aio import MessageBus

if TYPE_CHECKING:
    from collections.abc import Callable, Iterator

    PolicyRunner = Callable[[str, list[str]], tuple[int, str, list[tuple[str, str]]]]

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "modules/nixos/hardware/scripts/disable-bluetooth-pairing.sh"
POLICY = SCRIPT.with_suffix(".py")
ADAPTER = "org.bluez.Adapter1"
MANAGER = "org.freedesktop.DBus.ObjectManager"
PROPERTIES = "org.freedesktop.DBus.Properties"


@pytest.fixture
def private_bus(tmp_path: Path) -> Iterator[str]:
    """Start a private bus without contacting the host's Bluetooth service.

    Yields:
        The private bus address.

    """
    daemon = shutil.which("dbus-daemon")
    assert daemon is not None, "dbus-daemon is required"
    config = tmp_path / "bus.conf"
    config.write_text(
        "<busconfig><type>session</type><listen>unix:tmpdir=/tmp</listen>"
        '<auth>EXTERNAL</auth><policy context="default">'
        '<allow own="*"/><allow send_destination="*"/><allow receive_sender="*"/>'
        "</policy></busconfig>",
        encoding="utf-8",
    )
    with subprocess.Popen(  # ruff: ignore[subprocess-without-shell-equals-true] - Fixed executable, no shell input.
        [daemon, f"--config-file={config}", "--nofork", "--print-address=1"],
        stdout=subprocess.PIPE,
        text=True,
    ) as process:
        try:
            assert process.stdout is not None
            address = process.stdout.readline().strip()
            assert address.startswith("unix:"), "private D-Bus daemon did not start"
            yield address
        finally:
            process.terminate()
            process.wait(timeout=5)


@pytest.fixture
def run_policy(
    tmp_path: Path, private_bus: str, monkeypatch: pytest.MonkeyPatch
) -> PolicyRunner:
    """Run the actual shell entry point against a controllable BlueZ service.

    Returns:
        A policy runner reporting status, stderr, and service requests.

    """
    bash = shutil.which("bash")
    assert bash is not None
    adapters = tmp_path / "adapters"
    adapters.mkdir()
    # HCI child devices must not be mistaken for separate radio adapters.
    (adapters / "hci0:1").mkdir()
    script = tmp_path / "policy"
    script.write_text(
        Path(os.environ.get("TEST_PAIRING_SCRIPT", SCRIPT))
        .read_text(encoding="utf-8")
        .replace("@bash@", bash)
        .replace("@python@", sys.executable)
        .replace("@policyScript@", str(POLICY))
        .replace("/sys/class/bluetooth", str(adapters)),
        encoding="utf-8",
    )
    monkeypatch.setenv("DBUS_SYSTEM_BUS_ADDRESS", private_bus)
    monkeypatch.delenv("BASH_ENV", raising=False)
    monkeypatch.delenv("ENV", raising=False)

    async def scenario(
        mode: str, names: list[str]
    ) -> tuple[int, str, list[tuple[str, str]]]:
        for name in names:
            (adapters / name).mkdir()
        service = await MessageBus(bus_address=private_bus).connect()
        await service.request_name("org.bluez")
        calls: list[tuple[str, str]] = []
        scheduled: list[asyncio.TimerHandle] = []
        interface = {ADAPTER: {"Pairable": Variant("b", True)}}

        def publish(path: str, interfaces: dict[str, dict[str, Variant]]) -> None:
            service.send(
                Message.new_signal(
                    "/", MANAGER, "InterfacesAdded", "oa{sa{sv}}", [path, interfaces]
                )
            )

        def request(message: Message) -> Message | None:
            if message.message_type != MessageType.METHOD_CALL:
                return None
            calls.append((message.member or "", message.path or ""))
            if message.interface == MANAGER and message.member == "GetManagedObjects":
                if mode == "snapshot-error":
                    return Message.new_error(
                        message, "org.bluez.Error.Failed", "fixture failure"
                    )
                if mode in {"immediate", "set-error"}:
                    objects = {f"/org/bluez/{name}": interface for name in names}
                else:
                    objects = {}
                    if mode == "race":
                        publish("/org/bluez/hci0", interface)
                    elif mode == "unrelated":
                        publish("/org/bluez/hci0", {"org.bluez.Device1": {}})
                        publish("/org/bluez/hci9", interface)
                    elif mode == "delayed":
                        scheduled.extend(
                            asyncio.get_running_loop().call_later(
                                0.1, publish, f"/org/bluez/{name}", interface
                            )
                            for name in reversed(names)
                        )
                    elif mode == "duplicate":
                        publish("/org/bluez/hci0", interface)
                        publish("/org/bluez/hci0", interface)
                        objects = {"/org/bluez/hci0": interface}
                return Message.new_method_return(message, "a{oa{sa{sv}}}", [objects])
            if message.interface == PROPERTIES and message.member == "Set":
                assert message.body == [ADAPTER, "Pairable", Variant("b", False)]
                if mode == "set-error":
                    return Message.new_error(
                        message, "org.bluez.Error.NotAuthorized", "fixture denial"
                    )
                return Message.new_method_return(message)
            return Message.new_error(
                message,
                "org.freedesktop.DBus.Error.UnknownMethod",
                "unexpected request",
            )

        service.add_message_handler(request)
        process = None
        try:
            process = await asyncio.create_subprocess_exec(
                bash,
                str(script),
                "--timeout",
                "0.4",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                env=os.environ.copy(),
            )
            _, stderr = await asyncio.wait_for(process.communicate(), timeout=5)
            assert process.returncode is not None
            return process.returncode, stderr.decode(), calls
        finally:
            for timer in scheduled:
                timer.cancel()
            if process is not None and process.returncode is None:
                process.kill()
                await process.wait()
            service.disconnect()
            await service.wait_for_disconnect()

    def invoke(mode: str, names: list[str]) -> tuple[int, str, list[tuple[str, str]]]:
        return asyncio.run(scenario(mode, names))

    return invoke


@pytest.mark.parametrize("mode", ["immediate", "delayed", "race", "duplicate"])
def test_disables_pairing_once_without_readiness_probes(
    run_policy: PolicyRunner, mode: str
) -> None:
    """Cover existing objects and notifications before, during, and after snapshot."""
    status, stderr, calls = run_policy(mode, ["hci0"])
    assert status == 0, stderr
    assert calls == [("GetManagedObjects", "/"), ("Set", "/org/bluez/hci0")]


@pytest.mark.parametrize("mode", ["never", "unrelated", "snapshot-error", "set-error"])
def test_failure_is_bounded_and_visible(run_policy: PolicyRunner, mode: str) -> None:
    """Timeouts and rejected D-Bus calls must fail without repeated requests."""
    status, stderr, calls = run_policy(mode, ["hci0"])
    assert status != 0
    assert "pairing policy" in stderr
    assert calls.count(("GetManagedObjects", "/")) == 1
    expected = [("GetManagedObjects", "/")]
    if mode == "set-error":
        expected.append(("Set", "/org/bluez/hci0"))
    assert calls == expected


def test_all_adapters_receive_policy(run_policy: PolicyRunner) -> None:
    """Out-of-order adapter registration must apply each adapter exactly once."""
    status, stderr, calls = run_policy("delayed", ["hci0", "hci1"])
    assert status == 0, stderr
    assert sorted(calls) == [
        ("GetManagedObjects", "/"),
        ("Set", "/org/bluez/hci0"),
        ("Set", "/org/bluez/hci1"),
    ]


def test_no_adapters_needs_no_bus_calls(run_policy: PolicyRunner) -> None:
    """No hardware is a successful no-op, including unrelated HCI child nodes."""
    status, stderr, calls = run_policy("immediate", [])
    assert status == 0, stderr
    assert not calls
