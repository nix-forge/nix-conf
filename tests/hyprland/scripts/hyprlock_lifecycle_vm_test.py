"""Exercise real locker rejection and PAM inside a disposable graphics guest."""

from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from collections.abc import Callable

    from test_driver.machine import QemuMachine

    machine: QemuMachine = cast("QemuMachine", None)
    start_all: Callable[[], None] = cast("Callable[[], None]", None)

start_all()
machine.succeed("@command@", timeout=180)
