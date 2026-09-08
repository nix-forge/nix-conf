"""Exercise cancellation ordering and unsupported modifier IPC on an idle desktop.

Uses the isolated proxy/daemon from check_alt_tab_ipc_timeout.py and restores
the normal service and focus. Pass the binary and 'cancel' or 'legacy'.
"""

from __future__ import annotations

import json
import subprocess  # ruff: ignore[suspicious-subprocess-import] -- Explicit local IPC argv.
import sys
import time
from operator import itemgetter
from typing import TYPE_CHECKING

from check_alt_tab_ipc_timeout import (
    ALT,
    ESC,
    _check,  # ruff: ignore[import-private-name] -- Shared regression runner.
    _hypr,  # ruff: ignore[import-private-name] -- Shared regression helpers.
    _ipc,  # ruff: ignore[import-private-name] -- Shared regression helpers.
    _key,  # ruff: ignore[import-private-name] -- Shared regression helpers.
    _require,  # ruff: ignore[import-private-name] -- Shared regression helpers.
    _visible,  # ruff: ignore[import-private-name] -- Shared regression helpers.
    _wait_visible,  # ruff: ignore[import-private-name] -- Shared regression helpers.
)
from check_alt_tab_timing import RALT, SHIFT, TAB

if TYPE_CHECKING:
    from check_alt_tab_ipc_timeout import _Proxy

CLI_ARGUMENTS = 3


def _open_at(binary: str, env: dict[str, str], event_time: int) -> None:
    subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] -- Explicit local IPC argv.
        [
            binary,
            "socat",
            json.dumps({"OpenSwitch": {"reverse": False, "event_time": event_time}}),
        ],
        env=env,
        check=True,
        timeout=2,
    )


def _now() -> int:
    return int(time.monotonic() * 1000) & 0xFFFFFFFF


def _cancel(binary: str, env: dict[str, str], _proxy: _Proxy, fd: int) -> None:
    original = _hypr("activewindow").get("address")
    old_event = _now()
    _key(fd, ALT, 1)
    time.sleep(0.05)
    _open_at(binary, env, old_event)
    _wait_visible(True, 1, "Picker did not open")
    # Mapping precedes Wayland keyboard focus; cancel an established selection.
    time.sleep(0.2)
    _key(fd, ESC, 1)
    _key(fd, ESC, 0)
    _wait_visible(False, 1, "Escape did not close picker")
    _key(fd, ALT, 0)
    time.sleep(0.05)
    _open_at(binary, env, old_event)
    time.sleep(0.3)
    _require(not _visible(), "Delayed cancelled open left an overlay")
    _require(
        _hypr("activewindow").get("address") == original,
        "Delayed cancelled open changed focus",
    )
    sys.stdout.write(
        "PASS: delayed open from before Escape does not reopen or commit" + "\n"
    )

    clients = sorted(_hypr("clients"), key=itemgetter("focusHistoryID"))
    expected = clients[1]["address"]
    # A new quick chord may already be released when its open arrives.
    _open_at(binary, env, _now())
    time.sleep(0.3)
    _require(not _visible(), "New quick chord left an overlay")
    _require(
        _hypr("activewindow").get("address") == expected,
        "Cancellation swallowed the next quick chord",
    )
    sys.stdout.write("PASS: next quick chord after Escape still commits" + "\n")


def _legacy(binary: str, env: dict[str, str], proxy: _Proxy, fd: int) -> None:
    clients = sorted(_hypr("clients"), key=itemgetter("focusHistoryID"))
    expected = clients[1]["address"]
    proxy.unsupported.set()
    _key(fd, ALT, 1)
    time.sleep(0.05)
    _ipc(binary, env, None)
    _wait_visible(True, 1, "Picker did not open")
    time.sleep(0.2)
    _key(fd, ALT, 0)
    _wait_visible(False, 1, "Unsupported query prevented modifier-release commit")
    time.sleep(0.1)
    _require(
        _hypr("activewindow").get("address") == expected,
        "Legacy release focused the wrong window",
    )
    sys.stdout.write(
        "PASS: modifier release commits when the state-query command is unsupported\n"
    )

    for extra in (SHIFT, RALT, TAB):
        clients = sorted(_hypr("clients"), key=itemgetter("focusHistoryID"))
        expected = clients[1]["address"]
        _key(fd, ALT, 1)
        time.sleep(0.05)
        _ipc(binary, env, None)
        _wait_visible(True, 1, "Compatibility picker did not reopen")
        time.sleep(0.2)
        _key(fd, extra, 1)
        time.sleep(0.1)
        if extra == SHIFT:
            _key(fd, SHIFT, 0)
            time.sleep(0.1)
            _require(_visible(), "Shift release committed while Alt remained held")
        _key(fd, ALT, 0)
        if extra == RALT:
            time.sleep(0.1)
            _require(
                _visible(), "Left Alt release committed while right Alt remained held"
            )
            _key(fd, RALT, 0)
        _wait_visible(False, 1, "Compatibility release did not close the picker")
        _key(fd, extra, 0)
        time.sleep(0.1)
        # Pressing Tab navigates once more while the overlay owns focus.
        if extra == TAB:
            expected = clients[2 % len(clients)]["address"]
        _require(
            _hypr("activewindow").get("address") == expected,
            f"Compatibility release focused the wrong window with key {extra}",
        )
        sys.stdout.write(f"PASS: compatibility release with key {extra}\n")
    sys.stdout.write(
        "PASS: unsupported-query release respects Shift, both Alt sides, and held Tab\n"
    )


if __name__ == "__main__":
    _require(
        len(sys.argv) == CLI_ARGUMENTS and sys.argv[2] in {"cancel", "legacy"},
        "Usage: check_alt_tab_compatibility.py BINARY cancel|legacy",
    )
    _check(
        sys.argv[1],
        _cancel if sys.argv[2] == "cancel" else _legacy,
        expected_warnings=None,
    )
