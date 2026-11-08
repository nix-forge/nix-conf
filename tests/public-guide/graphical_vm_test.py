"""Validate generated artifacts in an isolated build or VM fixture."""

from typing import TYPE_CHECKING, Any, cast

if TYPE_CHECKING:
    from collections.abc import Callable

    from test_driver.machine import QemuMachine

    machine: QemuMachine = cast("QemuMachine", None)
    start_all: Callable[[], None] = cast("Callable[[], None]", None)

import json

start_all()
machine.wait_for_unit("home-manager-learner.service")
machine.succeed("su - learner -c 'foot --check-config'")
machine.wait_for_file("/run/user/1000/public-demo-sway.sock")
machine.succeed("loginctl list-sessions --no-legend | grep learner")
machine.succeed("pgrep -u learner -x sway")


def sway(command: str) -> str:
    """Send a command to the learner's compositor.

    Returns:
        The compositor response.

    """
    return machine.succeed("su - learner -c 'swaymsg " + command + "'")


def terminals() -> list[dict[str, Any]]:
    """Find terminal windows in the compositor tree.

    Returns:
        The matching window nodes.

    """
    tree = json.loads(sway("-t get_tree"))

    def visit(node: dict[str, Any]) -> list[dict[str, Any]]:
        found = [node] if node.get("app_id") in {"foot", "public-demo-terminal"} else []
        for child in node.get("nodes", []) + node.get("floating_nodes", []):
            found.extend(visit(child))
        return found

    return visit(tree)


machine.wait_until_succeeds(
    "su - learner -c 'swaymsg -t get_tree' | jq -e '.. | objects | select(.app_id? == \"public-demo-terminal\")'"
)
# Exercise the same keybinding that the guide asks a reader to use.
machine.send_key("alt-ret")
machine.wait_until_succeeds(
    "su - learner -c 'swaymsg -t get_tree' | jq -e '[.. | objects | select(.app_id? == \"foot\" or .app_id? == \"public-demo-terminal\")] | length == 2'"
)
assert len(terminals()) == 2
# Type into the focused real terminal, then inspect output written by its
# shell. A compositor process alone cannot satisfy this check.
machine.send_chars(
    "git init ~/practice && cd ~/practice && git st > ~/terminal-result\n"
)
machine.wait_until_succeeds(
    "grep -F 'No commits yet on main' /home/learner/terminal-result"
)
machine.succeed("su - learner -c 'test $(git config --global pull.rebase) = true'")
machine.fail("su - learner -c 'git config --global user.email'")
machine.send_key("alt-shift-q")
machine.wait_until_succeeds(
    "su - learner -c 'swaymsg -t get_tree' | jq -e '[.. | objects | select(.app_id? == \"foot\" or .app_id? == \"public-demo-terminal\")] | length == 1'"
)
machine.screenshot("public-demo")
