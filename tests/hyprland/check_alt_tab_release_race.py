"""Reproduce a delayed Alt+Tab open arriving after its release.

Pass a Hyprshell binary for the running daemon. This injects the real IPC
messages in the problematic order, briefly changes focus, and restores it.
Run while the desktop is idle and Alt is not held.
"""

import json
import shutil
import subprocess  # ruff: ignore[suspicious-subprocess-import] -- Tests local compositor and switcher IPC.
import sys
import time
from operator import itemgetter

CLI_ARGUMENTS = 2
RACE_ATTEMPTS = 30


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def _run(args: list[str]) -> str:
    return subprocess.check_output(args, text=True, timeout=5)  # ruff: ignore[subprocess-without-shell-equals-true] -- Explicit argv; no shell.


def _concurrent_pair(binary: str) -> None:
    """Send independently scheduled IPC messages and reap both clients."""
    opening = subprocess.Popen(  # ruff: ignore[subprocess-without-shell-equals-true] -- Fixed local IPC arguments, no shell.
        [binary, "socat", '{"OpenSwitch":{"reverse":false}}']
    )
    closing = None
    try:
        closing = subprocess.Popen(  # ruff: ignore[subprocess-without-shell-equals-true] -- Fixed local IPC arguments, no shell.
            [binary, "socat", '{"CloseSwitch":{"switch":true}}']
        )
        _require(opening.wait(timeout=5) == 0, "Open IPC failed")
        _require(closing.wait(timeout=5) == 0, "Close IPC failed")
    finally:
        # A stalled peer must not make Popen's context-manager exit
        # wait forever or leave the other client behind.
        children = [child for child in (opening, closing) if child is not None]
        for child in children:
            if child.poll() is None:
                child.kill()
        for child in children:
            child.wait(timeout=5)


def _check(binary: str, hyprctl: str) -> None:
    def ipc(message: dict) -> None:
        _run([binary, "socat", json.dumps(message)])

    def active() -> str | None:
        return json.loads(_run([hyprctl, "-j", "activewindow"])).get("address")

    def visible() -> bool:
        layers = json.loads(_run([hyprctl, "-j", "layers"]))
        return any(
            "hyprshell" in layer["namespace"]
            for monitor in layers.values()
            for level in monitor["levels"].values()
            for layer in level
        )

    keys = _run([
        hyprctl,
        "repl",
        'return hl.is_key_down("Alt_L") or hl.is_key_down("Alt_R")',
    ])
    _require(keys.strip() == "false", "Release Alt before running the test")
    ipc({"CloseSwitch": {"switch": False}})
    original = active()
    clients = sorted(
        json.loads(_run([hyprctl, "-j", "clients"])),
        key=itemgetter("focusHistoryID"),
    )
    _require(len(clients) > 1, "Need two ordinary open windows")
    _require(clients[0]["address"] == original, "Focus changed during test setup")
    expected = clients[1]["address"]
    try:
        # Separate exec_cmd processes can deliver exactly this ordering.
        ipc({"CloseSwitch": {"switch": True}})
        ipc({"OpenSwitch": {"reverse": False}})
        deadline = time.monotonic() + 1
        while time.monotonic() < deadline:
            if not visible() and active() == expected:
                sys.stdout.write(
                    "PASS: delayed open commits the recent window and leaves no overlay\n"
                )
                break
            time.sleep(0.02)
        _require(
            not visible(),
            "FAIL: delayed open left the switcher stuck after Alt release",
        )
        _require(
            active() == expected,
            f"FAIL: delayed open did not focus the recent window, expected {expected}, got {active()}",
        )
        for _ in range(RACE_ATTEMPTS):
            clients = sorted(
                json.loads(_run([hyprctl, "-j", "clients"])),
                key=itemgetter("focusHistoryID"),
            )
            expected = clients[1]["address"]
            # Match exec_cmd spawning independently scheduled IPC clients.
            _concurrent_pair(binary)
            deadline = time.monotonic() + 1
            while time.monotonic() < deadline and (visible() or active() != expected):
                time.sleep(0.02)
            _require(
                active() == expected,
                "FAIL: concurrent release focused the wrong window",
            )
            _require(not visible(), "FAIL: concurrent open/close left a stuck overlay")
        sys.stdout.write(
            f"PASS: {RACE_ATTEMPTS} concurrent open/release pairs focused the recent window and left no overlay\n"
        )
    finally:
        ipc({"CloseSwitch": {"switch": False}})
        if original is not None:
            _run([
                hyprctl,
                "dispatch",
                "hl.dsp.focus({window=" + json.dumps("address:" + original) + "})",
            ])


if __name__ == "__main__":
    hyprctl = shutil.which("hyprctl")
    if hyprctl is None or len(sys.argv) != CLI_ARGUMENTS:
        sys.exit("Usage: python3 check_alt_tab_release_race.py /path/to/hyprshell")
    _check(sys.argv[1], hyprctl)
