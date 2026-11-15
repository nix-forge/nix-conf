"""Validate generated artifacts in an isolated build or VM fixture."""

from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from collections.abc import Callable

    from test_driver.machine import QemuMachine

    machine: QemuMachine = cast("QemuMachine", None)
    start_all: Callable[[], None] = cast("Callable[[], None]", None)

start_all()
machine.wait_for_unit("multi-user.target")
machine.wait_for_unit("home-manager-learner.service")
machine.succeed(
    "su - learner -c 'test $(git config --global init.defaultBranch) = main'"
)
machine.succeed("su - learner -c 'test $(git config --global pull.ff) = only'")
machine.succeed(
    "su - learner -c 'git init ~/practice && cd ~/practice && git st' | grep 'No commits yet on main'"
)
machine.succeed(
    "su - learner -c \"bash -ic 'alias gs'\" | grep 'git status --short --branch'"
)
machine.succeed("su - learner -c 'starship module character' | grep '>'")
machine.fail("su - learner -c 'git config --global user.email'")
