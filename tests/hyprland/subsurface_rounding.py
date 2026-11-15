"""Compare compositor output with client geometry and a single-layer reference."""

# Commands and capture paths are fixed by the disposable VM, with no user input.
# ruff: file-ignore[suspicious-subprocess-import, subprocess-without-shell-equals-true, start-process-with-partial-path, hardcoded-temp-file]
import json
import os
import select
import subprocess
import sys
import time
from pathlib import Path
from typing import cast

from compositor_events import CompositorEvents, command_output
from PIL import Image

PIXEL_TOLERANCE = 2  # Allow work-buffer color conversion to round by two units.


PRINTABLE_ASCII_START = 32


def _command(*args: str) -> str:
    try:
        return command_output(*args)
    except subprocess.CalledProcessError as error:
        output = error.output or b""
        if isinstance(output, bytes):
            output = output.decode("utf-8", errors="replace")
        # The reply was captured by the existing observer but its traceback
        # omits it. Preserve the bounded actual IPC diagnostic before failing.
        diagnostic = "".join(
            char
            for char in output[:4096]
            if char in "\n\t" or ord(char) >= PRINTABLE_ASCII_START
        )
        print(  # ruff: ignore[print] -- Bounded owned IPC failure evidence.
            f"Compositor command rejected (exit {error.returncode}): {diagnostic}",
            file=sys.stderr,
        )
        raise


def _pixel(image: Image.Image, xy: tuple[int, int]) -> tuple[int, int, int]:
    return cast("tuple[int, int, int]", image.getpixel(xy))


def _configure_geometry(address: str) -> None:
    """Set the captured window geometry through selected typed Lua dispatchers."""
    selector = json.dumps(address)
    _command(
        "hyprctl", "dispatch", f'hl.dsp.window.float{{action="on",window={selector}}}'
    )
    _command(
        "hyprctl",
        "dispatch",
        f"hl.dsp.window.resize{{x=480,y=320,relative=false,window={selector}}}",
    )
    _command(
        "hyprctl",
        "dispatch",
        f"hl.dsp.window.move{{x=20,y=20,relative=false,window={selector}}}",
    )


def _capture(mode: int, radius: int, scale: float) -> tuple[Image.Image, int, int]:
    _command("hyprctl", "eval", f"hl.config({{decoration={{rounding={radius}}}}})")
    option = json.loads(_command("hyprctl", "getoption", "decoration:rounding", "-j"))
    assert option["int"] == radius, option
    process = subprocess.Popen(["subsurface-rounding-client", str(mode)])
    try:
        matches: list[dict] = []

        def mapped() -> bool:
            nonlocal matches
            clients = json.loads(changes.command("hyprctl", "clients", "-j"))
            matches = [c for c in clients if c["class"] == "rounding-fixture"]
            return bool(matches)

        with CompositorEvents() as changes:
            changes.wait(mapped, timeout=10)
        client = matches[0]
        address = "address:" + client["address"]
        _configure_geometry(address)
        time.sleep(0.5)
        client = next(
            c
            for c in json.loads(_command("hyprctl", "clients", "-j"))
            if c["address"] == client["address"]
        )
        assert client["size"] == [480, 320], client
        blur = os.environ.get("REPRO_BLUR", "0")
        filename = f"/tmp/fixture-{scale}-{blur}-{radius}-{mode}.png"
        _command("grim", filename)
        image = Image.open(filename).convert("RGB")
        x, y = [round(p * scale) for p in client["at"]]
        return image, x, y
    finally:
        descriptor = os.pidfd_open(process.pid)
        try:
            process.terminate()
            if not select.select([descriptor], [], [], 5)[0]:
                process.kill()
            process.wait()
        finally:
            os.close(descriptor)


def _interior_failures(scale: float) -> list[str]:
    # A square child must retain its own shape at every corner.
    image, x, y = _capture(1, 16, scale)
    reference, rx, ry = _capture(1, 0, scale)
    failures = []
    for cx, cy in [(102, 102), (217, 102), (102, 157), (217, 157)]:
        dx, dy = round(cx * scale), round(cy * scale)
        actual = _pixel(image, (x + dx, y + dy))
        expected = _pixel(reference, (rx + dx, ry + dy))
        assert expected == (0, 255, 0), ("invalid square child reference", expected)
        if actual != expected:
            failures.append(f"child {cx},{cy}: {actual}, expected {expected}")
    return failures


def _edge_failures(scale: float, reference_mode: int, tree_mode: int) -> list[str]:
    # Two identical opaque layers must match a single layer at the parent edge.
    one, ox, oy = _capture(reference_mode, 16, scale)
    two, tx, ty = _capture(tree_mode, 16, scale)
    failures = []
    width, height = round(480 * scale), round(320 * scale)
    for px in range(round(20 * scale)):
        for py in range(round(20 * scale)):
            corners = [
                (px, py),
                (width - 1 - px, py),
                (px, height - 1 - py),
                (width - 1 - px, height - 1 - py),
            ]
            for dx, dy in corners:
                differences = (
                    abs(a - b)
                    for a, b in zip(
                        _pixel(one, (ox + dx, oy + dy)),
                        _pixel(two, (tx + dx, ty + dy)),
                        strict=True,
                    )
                )
                if max(differences) > PIXEL_TOLERANCE:
                    failures.append(f"parent edge {dx},{dy}")
    return failures


def _verify(scale: float) -> None:
    failures = _interior_failures(scale)
    # Match independent single-layer references with opaque and alpha overlap.
    for reference_mode, tree_mode in [(0, 2), (0, 5), (8, 7), (0, 9)]:
        failures.extend(_edge_failures(scale, reference_mode, tree_mode))
    # A child straddling a corner must retain its permitted out-of-parent area.
    overflow, vx, vy = _capture(3, 16, scale)
    assert _pixel(overflow, (vx - round(10 * scale), vy - round(10 * scale))) == (
        0,
        255,
        0,
    ), "out-of-parent corner overflow"
    # The former bounds clamp cut off right/bottom overflow even at radius zero.
    outside, bx, by = _capture(4, 16, scale)
    if _pixel(outside, (bx + round(500 * scale), by + round(330 * scale))) != (
        0,
        255,
        0,
    ):
        failures.append("right/bottom overflow")
    if failures:
        message = f"scale {scale}: {failures[:12]} ({len(failures)} wrong pixels)"
        raise AssertionError(message)


if __name__ == "__main__":
    scale = float(os.environ.get("REPRO_SCALE", "1"))
    _command(
        "hyprctl",
        "eval",
        f'hl.monitor({{output="", mode="preferred", position="auto", scale={scale}}})',
    )
    time.sleep(0.5)
    monitors = json.loads(_command("hyprctl", "monitors", "-j"))
    assert monitors, monitors
    assert monitors[0]["scale"] == scale, monitors
    blur_enabled = "true" if os.environ.get("REPRO_BLUR", "0") == "1" else "false"
    _command(
        "hyprctl",
        "eval",
        f"hl.config({{decoration={{blur={{enabled={blur_enabled}}}}}}})",
    )
    option = json.loads(
        _command("hyprctl", "getoption", "decoration:blur:enabled", "-j")
    )
    assert option["bool"] == (blur_enabled == "true"), option
    _verify(scale)
    Path("/tmp/fixture-verdict.txt").write_text(
        f"PASS at scale {scale}\n", encoding="utf-8"
    )
