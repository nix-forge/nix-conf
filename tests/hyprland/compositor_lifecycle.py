"""Observe nested compositor startup and exit for the shell that owns it."""

from __future__ import annotations

import argparse
import json
import os
import select
from pathlib import Path
from time import monotonic

from compositor_events import CompositorEvents
from notification_process import run as run_command
from waits import FileChanges

LOCK_LINES = 2


def _startup(args: argparse.Namespace) -> None:
    deadline = monotonic() + 120
    instance: dict = {}
    socket = None

    def connected() -> bool:
        nonlocal instance, socket
        remaining = deadline - monotonic()
        if remaining <= 0:
            return False
        # Hyprland publishes this lock after socket2 is listening. Its two
        # native lines also avoid hyprctl's malformed empty-instance JSON.
        for lock in (args.runtime / "hypr").glob("*/hyprland.lock"):
            try:
                lines = lock.read_text().splitlines()
            except FileNotFoundError:
                lines = []
            if len(lines) != LOCK_LINES or lines[0] != str(args.pid) or not lines[1]:
                continue
            instance = {
                "pid": args.pid,
                "instance": lock.parent.name,
                "wl_socket": lines[1],
            }
            socket = lock.parent / ".socket2.sock"
            return True
        return False

    FileChanges(args.runtime, args.evidence).wait(
        connected, timeout=max(0, deadline - monotonic())
    )
    assert socket is not None
    with CompositorEvents(socket) as changes:
        created = not args.headless

        def monitors_ready() -> bool:
            nonlocal created
            if not created:
                response = changes.command(
                    "hyprctl",
                    "-i",
                    instance["instance"],
                    "output",
                    "create",
                    "headless",
                    "HEADLESS-TEST",
                )
                if response.strip() != "ok":
                    message = f"Headless output creation failed: {response}"
                    raise RuntimeError(message)
                created = True
            monitors = json.loads(
                changes.command("hyprctl", "-i", instance["instance"], "monitors", "-j")
            )
            return bool(monitors) and all(
                monitor["name"].startswith(("WAYLAND-", "HEADLESS-"))
                for monitor in monitors
            )

        changes.wait(monitors_ready, timeout=max(0, deadline - monotonic()))
    print(json.dumps(instance))  # ruff: ignore[print] -- Structured result consumed by the owning shell.


def main() -> None:
    """Keep final waitpid ownership in the calling shell.

    Raises:
        TimeoutError: The compositor does not exit within ten seconds.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["startup", "exit"])
    parser.add_argument("pid", type=int)
    parser.add_argument("--runtime", type=Path)
    parser.add_argument("--evidence", type=Path)
    parser.add_argument("--headless", action="store_true")
    parser.add_argument("--instance")
    args = parser.parse_args()
    if args.mode == "startup":
        _startup(args)
    else:
        fd = os.pidfd_open(args.pid)
        try:
            deadline = monotonic() + 10
            run_command(
                ["hyprctl", "-i", args.instance, "dispatch", "hl.dsp.exit()"],
                check=True,
                capture_output=True,
                timeout=2,
            )
            remaining = deadline - monotonic()
            if remaining <= 0 or not select.select([fd], [], [], remaining)[0]:
                message = "Compositor did not exit within ten seconds"
                raise TimeoutError(message)
        finally:
            os.close(fd)


if __name__ == "__main__":
    main()
