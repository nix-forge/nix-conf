"""Check missed Alt-release recovery with real keyboard timing.

Run on an idle Hyprland desktop with at least two ordinary windows and write
access to /dev/uinput. Uses a fixed seed and restores focus and keyboard state.
The 45 ms hold / 5 ms release gap reproduced stuck overlays on the old build.

    python3 tests/hyprland/check_alt_tab_timing.py
"""

from __future__ import annotations

import fcntl
import json
import os
import random
import shutil
import struct
import subprocess  # ruff: ignore[suspicious-subprocess-import] -- Local compositor IPC with explicit argv.
import sys
import time
from contextlib import contextmanager
from operator import itemgetter
from typing import TYPE_CHECKING, Literal, overload

if TYPE_CHECKING:
    from collections.abc import Iterator

TAB, ALT, SHIFT, ESC, RALT = 15, 56, 42, 1, 100
KEYS = (TAB, ALT, SHIFT, ESC, RALT)
ATTEMPTS = 200
MIN_WINDOWS = 2


def _hyprctl() -> str:
    executable = shutil.which("hyprctl")
    if executable is None:
        message = "hyprctl is required"
        raise SystemExit(message)
    return executable


HYPRCTL = _hyprctl()


def _run(*args: str) -> str:
    return subprocess.check_output(args, text=True, timeout=5)  # ruff: ignore[subprocess-without-shell-equals-true] -- Explicit argv, no shell.


@overload
def _hypr(command: Literal["clients"]) -> list[dict]: ...


@overload
def _hypr(command: Literal["activewindow", "layers"]) -> dict: ...


def _hypr(command: str) -> dict | list[dict]:
    result = json.loads(_run(HYPRCTL, "-j", command))
    if command == "clients":
        if isinstance(result, list) and all(
            isinstance(client, dict) for client in result
        ):
            return result
    elif isinstance(result, dict):
        return result
    message = f"Unexpected JSON response to hyprctl {command}"
    raise TypeError(message)


def _visible() -> bool:
    return any(
        "hyprshell" in layer["namespace"]
        for monitor in _hypr("layers").values()
        for level in monitor["levels"].values()
        for layer in level
    )


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


@contextmanager
def _keyboard() -> Iterator[int]:
    fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
    created = False
    try:
        fcntl.ioctl(fd, 0x40045564, 1)
        for code in KEYS:
            fcntl.ioctl(fd, 0x40045565, code)
        os.write(
            fd,
            struct.pack("80sHHHHi", b"Alt Tab timing regression", 3, 1, 1, 1, 0)
            + bytes(64 * 4 * 4),
        )
        fcntl.ioctl(fd, 0x5501)
        created = True
        time.sleep(0.4)
        yield fd
    finally:
        if created:
            try:
                for code in KEYS:
                    _key(fd, code, 0)
                time.sleep(0.15)
                if _visible():
                    _key(fd, ESC, 1)
                    _key(fd, ESC, 0)
                    time.sleep(0.15)
            finally:
                fcntl.ioctl(fd, 0x5502)
        os.close(fd)


def _key(fd: int, code: int, value: int) -> None:
    os.write(fd, struct.pack("llHHi", 0, 0, 1, code, value))
    os.write(fd, struct.pack("llHHi", 0, 0, 0, 0, 0))


def _closed(label: str) -> None:
    deadline = time.monotonic() + 1
    while _visible() and time.monotonic() < deadline:
        time.sleep(0.02)
    _require(not _visible(), f"FAIL: switcher stuck with keys released: {label}")


def _check(fd: int) -> None:
    # The recovery check must allow an intentional hold and respect Escape.
    original = _hypr("activewindow").get("address")
    _key(fd, ALT, 1)
    _key(fd, TAB, 1)
    time.sleep(0.06)
    _key(fd, TAB, 0)
    time.sleep(0.6)
    _require(_visible(), "Switcher closed while Alt was still held")
    _key(fd, ESC, 1)
    _key(fd, ESC, 0)
    time.sleep(0.1)
    _closed("Escape with Alt held")
    _key(fd, ALT, 0)
    time.sleep(0.2)
    _require(
        _hypr("activewindow").get("address") == original,
        "An old recovery check switched focus after Escape",
    )
    sys.stdout.write(
        "PASS: held Alt keeps picker open; Escape cancels without late switching\n"
    )
    sys.stdout.flush()

    rng = random.Random(917)  # ruff: ignore[suspicious-non-cryptographic-random-usage] -- Fixed test timings, not cryptography.
    for attempt in range(ATTEMPTS):
        clients = sorted(_hypr("clients"), key=itemgetter("focusHistoryID"))
        expected = clients[1]["address"]
        if attempt % 2 == 0:
            alt, order, hold, gap = ALT, (ALT, TAB), 0.045, 0.005
        else:
            alt = rng.choice((ALT, RALT))
            order = rng.choice(((TAB, alt), (alt, TAB)))
            hold = rng.choice((0.001, 0.003, 0.006, 0.01, 0.015, 0.02, 0.03, 0.06))
            gap = rng.choice((0, 0.001, 0.005, 0.015))
        _key(fd, alt, 1)
        time.sleep(0.002)
        _key(fd, TAB, 1)
        time.sleep(hold)
        _key(fd, order[0], 0)
        time.sleep(gap)
        _key(fd, order[1], 0)
        time.sleep(0.12)
        deadline = time.monotonic() + 1
        while (
            _hypr("activewindow").get("address") != expected
            and time.monotonic() < deadline
        ):
            time.sleep(0.01)
        _require(
            _hypr("activewindow").get("address") == expected,
            f"Timed chord did not select the recent window: attempt={attempt}",
        )
        _closed(
            f"attempt={attempt}, Alt={alt}, release={order}, hold={hold}, gap={gap}"
        )
    sys.stdout.write(
        f"PASS: {ATTEMPTS} timed chords selected the recent window and left no overlay\n"
    )


def _main() -> None:
    _require(HYPRCTL is not None, "hyprctl is required")
    _require(len(_hypr("clients")) >= MIN_WINDOWS, "Need two ordinary windows")
    keys = _run(
        HYPRCTL,
        "repl",
        'return hl.is_key_down("Alt_L") or hl.is_key_down("Alt_R") or hl.is_key_down("Tab")',
    )
    _require(keys.strip() == "false", "Release Alt and Tab before this test")
    _require(not _visible(), "Close the switcher before this test")
    original = _hypr("activewindow").get("address")
    try:
        with _keyboard() as fd:
            _check(fd)
    finally:
        if isinstance(original, str) and original in {
            client["address"] for client in _hypr("clients")
        }:
            _run(
                HYPRCTL,
                "dispatch",
                "hl.dsp.focus({window=" + json.dumps("address:" + original) + "})",
            )


if __name__ == "__main__":
    _main()
