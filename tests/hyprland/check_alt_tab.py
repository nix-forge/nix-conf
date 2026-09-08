"""Exercise live Alt+Tab through a temporary uinput keyboard.

Run on an idle Hyprland 0.56+ desktop with at least three ordinary windows
and write access to /dev/uinput. This briefly changes focus, restores the
original window, and prints no window titles. It needs only Python's stdlib.

    python3 tests/hyprland/check_alt_tab.py
"""

import fcntl
import json
import os
import shutil
import struct
import subprocess  # ruff: ignore[suspicious-subprocess-import] -- Invokes local Hyprland IPC without a shell.
import sys
import time
from operator import itemgetter
from typing import Literal, overload

TAB, ALT, SHIFT, ESC, RALT = 15, 56, 42, 1, 100
MIN_WINDOWS = 3


def _hyprctl() -> str:
    executable = shutil.which("hyprctl")
    if executable is None:
        message = "hyprctl is required"
        raise SystemExit(message)
    return executable


HYPRCTL = _hyprctl()


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


@overload
def _hypr(command: Literal["clients"]) -> list[dict]: ...


@overload
def _hypr(command: Literal["activewindow", "layers"]) -> dict: ...


def _hypr(command: str) -> dict | list[dict]:
    result = json.loads(subprocess.check_output([HYPRCTL, "-j", command], timeout=5))  # ruff: ignore[subprocess-without-shell-equals-true] -- Fixed IPC arguments without a shell.
    if command == "clients":
        if isinstance(result, list) and all(
            isinstance(client, dict) for client in result
        ):
            return result
    elif isinstance(result, dict):
        return result
    message = f"Unexpected JSON response to hyprctl {command}"
    raise TypeError(message)


def _active() -> str:
    return str(_hypr("activewindow").get("address", ""))


def _focus(address: str) -> None:
    subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] -- JSON-escaped window selector, no shell.
        [
            HYPRCTL,
            "dispatch",
            "hl.dsp.focus({window=" + json.dumps("address:" + address) + "})",
        ],
        check=True,
        stdout=subprocess.DEVNULL,
    )
    time.sleep(0.12)
    _require(
        _active() == address,
        "Could not establish test focus; keep the desktop idle during this test",
    )


def _key(code: int, value: int) -> None:
    os.write(fd, struct.pack("llHHi", 0, 0, 1, code, value))
    os.write(fd, struct.pack("llHHi", 0, 0, 0, 0, 0))


def _tap(code: int = TAB, delay: float = 0.03) -> None:
    _key(code, 1)
    time.sleep(delay)
    _key(code, 0)


def _expect(address: str, label: str) -> None:
    time.sleep(0.25)
    deadline = time.monotonic() + 1
    actual = _active()
    while actual != address and time.monotonic() < deadline:
        time.sleep(0.02)
        actual = _active()
    _require(actual == address, f"{label}: expected {address}, got {actual}")
    _require(
        "hyprshell" not in json.dumps(_hypr("layers")),
        f"{label}: switcher remained visible",
    )
    sys.stdout.write(f"PASS: {label}\n")
    sys.stdout.flush()


def _prepare() -> list[str]:
    # Deliberately use recency opposite to workspace order.
    clients = sorted(_hypr("clients"), key=lambda c: c["workspace"]["id"])
    _require(len(clients) >= MIN_WINDOWS, "Need at least three open windows")
    for c in [clients[1], clients[-1], clients[0]]:
        _focus(c["address"])
    order = [
        c["address"] for c in sorted(_hypr("clients"), key=itemgetter("focusHistoryID"))
    ]
    _require(
        order[:2] == [clients[0]["address"], clients[-1]["address"]],
        "Focus history changed during setup; keep the desktop idle",
    )
    return order


original = _active()
fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
fcntl.ioctl(fd, 0x40045564, 1)
for code in [TAB, ALT, SHIFT, ESC, RALT]:
    fcntl.ioctl(fd, 0x40045565, code)
os.write(
    fd,
    struct.pack("80sHHHHi", b"Alt Tab regression keyboard", 3, 1, 1, 1, 0)
    + bytes(64 * 4 * 4),
)
fcntl.ioctl(fd, 0x5501)
time.sleep(0.4)
try:
    order = _prepare()
    _key(ALT, 1)
    _key(TAB, 1)
    time.sleep(0.15)
    _key(ALT, 0)
    _expect(order[1], "Alt release commits while Tab remains held")
    _key(TAB, 0)
    _expect(order[1], "releasing Tab afterward preserves the selected window")
    order = _prepare()
    _key(RALT, 1)
    _key(TAB, 1)
    time.sleep(0.15)
    _key(RALT, 0)
    _expect(order[1], "right Alt release commits while Tab remains held")
    _key(TAB, 0)
    order = _prepare()
    _key(ALT, 1)
    _key(SHIFT, 1)
    _key(TAB, 1)
    time.sleep(0.15)
    _key(ALT, 0)
    _expect(order[-1], "reverse selection commits while Shift and Tab remain held")
    _key(TAB, 0)
    _key(SHIFT, 0)
    order = _prepare()
    _key(ALT, 1)
    _key(RALT, 1)
    _key(TAB, 1)
    time.sleep(0.15)
    _key(ALT, 0)
    time.sleep(0.05)
    _require(
        "hyprshell" in json.dumps(_hypr("layers")),
        "Keep the picker open while the other Alt remains held",
    )
    _key(RALT, 0)
    _expect(order[1], "releasing the final Alt commits with Tab still held")
    _key(TAB, 0)
    order = _prepare()
    _key(ALT, 1)
    _tap()
    time.sleep(0.15)
    _key(ALT, 0)
    _expect(order[1], "recent window on Alt release")
    _key(ALT, 1)
    _tap()
    _key(ALT, 0)
    _expect(order[0], "second tap returns to original window")
    order = _prepare()
    _key(ALT, 1)
    _tap()
    time.sleep(0.2)
    _tap()
    time.sleep(0.1)
    _key(ALT, 0)
    _expect(order[2], "hold Alt and Tab twice cycles forward")
    order = _prepare()
    _key(ALT, 1)
    _key(SHIFT, 1)
    _tap()
    time.sleep(0.15)
    _key(SHIFT, 0)
    _key(ALT, 0)
    _expect(order[-1], "reverse entry, Shift released first")
    order = _prepare()
    _key(ALT, 1)
    _key(SHIFT, 1)
    _tap()
    time.sleep(0.15)
    _key(ALT, 0)
    _expect(order[-1], "reverse entry commits with Shift still held")
    _key(SHIFT, 0)
    order = _prepare()
    _key(ALT, 1)
    _tap()
    time.sleep(0.2)
    _key(SHIFT, 1)
    _tap()
    _key(SHIFT, 0)
    time.sleep(0.1)
    _key(ALT, 0)
    _expect(order[0], "reverse direction while switcher is open")
    order = _prepare()
    _key(ALT, 1)
    _tap()
    time.sleep(0.2)
    _tap(ESC)
    time.sleep(0.1)
    _key(ALT, 0)
    _expect(order[0], "Escape cancels")
    order = _prepare()
    for i in range(10):
        _key(ALT, 1)
        _tap(delay=0.01)
        _key(ALT, 0)
        _expect(order[1 if i % 2 == 0 else 0], f"quick tap {i + 1}")
finally:
    try:
        layers = json.dumps(_hypr("layers"))
        if "hyprshell" in layers or "noctalia-window-switcher" in layers:
            _tap(ESC)
    finally:
        try:
            for code in [TAB, ALT, SHIFT, RALT]:
                _key(code, 0)
            time.sleep(0.1)
            if isinstance(original, str) and original in {
                c["address"] for c in _hypr("clients")
            }:
                _focus(original)
        finally:
            fcntl.ioctl(fd, 0x5502)
            os.close(fd)
