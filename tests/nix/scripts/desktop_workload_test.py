"""Verify the production runner's lifecycle in an isolated systemd user session."""

from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from collections.abc import Callable

    from test_driver.machine import QemuMachine

    machine: QemuMachine = cast("QemuMachine", None)
    start_all: Callable[[], None] = cast("Callable[[], None]", None)

start_all()
machine.wait_for_unit("multi-user.target")
machine.wait_for_unit("user@1000.service")
machine.succeed(
    "runuser -u fixture -- env XDG_RUNTIME_DIR=/run/user/1000 "
    "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus "
    "systemctl --user start dbus.socket"
)
machine.succeed(
    "runuser -u fixture -- env XDG_RUNTIME_DIR=/run/user/1000 "
    "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus "
    "/run/current-system/sw/bin/workstation-native-check"
)
