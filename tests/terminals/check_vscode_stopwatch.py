"""Render nom's stopwatch in an isolated VS Code terminal and check its shape.

Requires a graphical session, code, Pillow, and websocket-client. No extensions
or user terminal sessions are loaded. --settings accepts generated HM settings.
"""

from __future__ import annotations

import argparse
import base64
import contextlib
import io
import json
import os
import shutil
import socket
import subprocess  # ruff: ignore[suspicious-subprocess-import] -- Runs the selected local VS Code binary.
import sys
import tempfile
import time
import urllib.request
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Callable

import websocket
from PIL import Image, ImageChops

INK_THRESHOLD = 35
MIN_ASPECT_RATIO = 0.7


class _CDP:
    def __init__(self, url: str) -> None:
        self.ws = websocket.create_connection(url, suppress_origin=True, timeout=15)
        self.sequence = 0

    def call(self, method: str, params: dict | None = None) -> dict:
        self.sequence += 1
        self.ws.send(
            json.dumps({"id": self.sequence, "method": method, "params": params or {}})
        )
        while True:
            result = json.loads(self.ws.recv())
            if result.get("id") == self.sequence:
                if "error" in result:
                    raise RuntimeError(result["error"])
                return result.get("result", {})

    def evaluate(self, expression: str) -> dict | str | bool | None:
        result = self.call(
            "Runtime.evaluate", {"expression": expression, "returnByValue": True}
        )
        if "exceptionDetails" in result:
            raise RuntimeError(result["exceptionDetails"])
        return result["result"].get("value")

    def key(self, name: str, code: int) -> None:
        for event in ("keyDown", "keyUp"):
            self.call(
                "Input.dispatchKeyEvent",
                {
                    "type": event,
                    "key": name,
                    "code": name,
                    "windowsVirtualKeyCode": code,
                },
            )


def _wait_for[T](callback: Callable[[], T | None], timeout: float = 30) -> T:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            result = callback()
            if result:
                return result
        except (OSError, ValueError):
            time.sleep(0.2)
        time.sleep(0.2)
    message = "VS Code diagnostic window did not become ready"
    raise TimeoutError(message)


def _close(cdp: _CDP | None, output: Path) -> None:
    """Retain best-effort diagnostics and always close the test connection."""
    if cdp:
        try:
            # Diagnostic capture must not prevent application cleanup
            # or replace the original rendering failure.
            with contextlib.suppress(
                OSError, websocket.WebSocketException, RuntimeError
            ):
                if not (output / "terminal.png").exists():
                    (output / "failure.png").write_bytes(
                        base64.b64decode(cdp.call("Page.captureScreenshot")["data"])
                    )
                    (output / "failure.txt").write_text(
                        str(cdp.evaluate("document.body.innerText"))
                    )
        finally:
            try:
                with contextlib.suppress(
                    OSError, websocket.WebSocketException, RuntimeError
                ):
                    cdp.call("Browser.close")
            finally:
                cdp.ws.close()


def _main() -> int:  # ruff: ignore[too-many-statements, too-many-locals] -- Keep the isolated application lifecycle and cleanup together.
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--settings", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--code", default="code")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    source = json.loads(args.settings.read_text())
    # Copy appearance only. Shell startup, extensions, tasks, and workspace
    # settings must not execute in this rendering test.
    keys = [
        "editor.fontFamily",
        "terminal.integrated.fontFamily",
        "terminal.integrated.fontLigatures.enabled",
        "terminal.integrated.gpuAcceleration",
        "terminal.integrated.rescaleOverlappingGlyphs",
        "terminal.integrated.minimumContrastRatio",
    ]
    settings = {key: source[key] for key in keys if key in source}
    with tempfile.TemporaryDirectory(prefix="vscode-stopwatch-") as temporary:
        root = Path(temporary)
        user = root / "profile/User"
        user.mkdir(parents=True)
        workspace = root / "workspace"
        workspace.mkdir()
        sample = root / "sample.sh"
        sample.write_text(
            "printf '\\033[2J\\033[H\\033[1m⏱ 24s\\033[0m    bare bold\\n"
            "⏱ 24s    bare normal\\n⏱︎ 24s    text selector\\n"
            "⏱️ 24s    emoji selector\\n😀 ❤️ 1️⃣ 🇺🇸 👩‍💻    emoji\\n"
            "0123456789 ABCDEFG abcdefg\\n┌─┬─┐  ❯      symbols\\n'\n"  # ruff: ignore[ambiguous-unicode-character-string] -- Literal glyph fixtures.
            "read -r unused\n"
        )
        os_name = "osx" if sys.platform == "darwin" else "linux"
        settings.update({
            "terminal.integrated.fontSize": 16,
            "terminal.integrated.lineHeight": 1.1,
            "terminal.integrated.letterSpacing": 0,
            "terminal.integrated.shellIntegration.enabled": False,
            f"terminal.integrated.defaultProfile.{os_name}": "font-audit",
            f"terminal.integrated.profiles.{os_name}": {
                "font-audit": {
                    "path": shutil.which("bash"),
                    "args": ["--noprofile", "--norc", str(sample)],
                },
            },
            "security.workspace.trust.enabled": False,
            "workbench.startupEditor": "none",
            "workbench.welcomePage.experimentalOnboarding": False,
            "window.restoreWindows": "none",
            "telemetry.telemetryLevel": "off",
            "update.mode": "none",
        })
        (user / "settings.json").write_text(json.dumps(settings))
        (user / "keybindings.json").write_text(
            json.dumps([
                {"key": "f6", "command": "workbench.action.terminal.new"},
                {"key": "f7", "command": "workbench.action.toggleMaximizedPanel"},
            ])
        )
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            port = listener.getsockname()[1]
        cdp = None
        env = os.environ.copy()
        # --noprofile/--norc do not disable BASH_ENV for a script shell.
        for name in ("BASH_ENV", "ENV"):
            env.pop(name, None)
        with (args.output / "code.log").open("w") as log:
            subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] -- Fixed arguments; no shell.
                [
                    args.code,
                    f"--user-data-dir={root / 'profile'}",
                    f"--extensions-dir={root / 'extensions'}",
                    "--disable-extensions",
                    "--new-window",
                    f"--remote-debugging-port={port}",
                    str(workspace),
                ],
                env=env,
                stdout=log,
                stderr=subprocess.STDOUT,
                check=True,
                timeout=30,
            )
            try:

                def page() -> dict | None:
                    with urllib.request.urlopen(
                        f"http://127.0.0.1:{port}/json/list", timeout=1
                    ) as response:
                        return next(
                            (p for p in json.load(response) if p["type"] == "page"),
                            None,
                        )

                cdp = _CDP(_wait_for(page)["webSocketDebuggerUrl"])
                _wait_for(
                    lambda: cdp.evaluate(
                        "!!document.querySelector('.monaco-workbench')"
                    )
                )
                # Allow startup contributions and the diagnostic keybindings to load.
                time.sleep(5)
                cdp.evaluate(
                    "[...document.querySelectorAll('button, a, [role=button]')].find(e => e.textContent.trim() === 'Continue without Signing In')?.click()"
                )
                time.sleep(0.5)
                # Dismissing first-run onboarding can reload the workbench.
                # Retry until the terminal exists, then wait for its renderer.
                for _ in range(10):
                    if cdp.evaluate("!!document.querySelector('.xterm')"):
                        break
                    cdp.key("F6", 117)
                    time.sleep(1)
                _wait_for(
                    lambda: cdp.evaluate(
                        "!!document.querySelector('.xterm-screen canvas')"
                    )
                )
                time.sleep(2)
                cdp.key("F7", 118)
                time.sleep(0.5)
                rect = cdp.evaluate(
                    "document.querySelector('.xterm-screen').getBoundingClientRect().toJSON()"
                )
                if not isinstance(rect, dict):
                    message = "VS Code did not return the terminal bounds"
                    raise TypeError(message)
                width = min(560, rect["width"])
                result = cdp.call(
                    "Page.captureScreenshot",
                    {
                        "clip": {
                            "x": rect["x"],
                            "y": rect["y"],
                            "width": width,
                            "height": 190,
                            "scale": 1,
                        }
                    },
                )
                data = base64.b64decode(result["data"])
                (args.output / "terminal.png").write_bytes(data)
                image = Image.open(io.BytesIO(data)).convert("RGB")
                scale = image.width / width
                # First two cells contain the bare bold stopwatch and a space.
                # Exclude the adjacent digits; 18 CSS pixels at this test font size.
                glyph = image.crop((0, 0, int(18 * scale), int(22 * scale)))
                background = Image.new("RGB", glyph.size, image.getpixel((0, 0)))
                mask = (
                    ImageChops
                    .difference(glyph, background)
                    .convert("L")
                    .point(lambda x: 255 if x > INK_THRESHOLD else 0)
                )
                bounds = mask.getbbox()
                if not bounds:
                    message = "The terminal did not paint the stopwatch fixture"
                    raise RuntimeError(message)
                w, h = bounds[2] - bounds[0], bounds[3] - bounds[1]
                metrics = {
                    "width": w,
                    "height": h,
                    "ratio": round(w / h, 3),
                    "pass": w / h >= MIN_ASPECT_RATIO,
                }
                (args.output / "results.json").write_text(
                    json.dumps(metrics, indent=2) + "\n"
                )
                sys.stdout.write(json.dumps(metrics) + "\n")
                return 0 if metrics["pass"] else 1
            finally:
                _close(cdp, args.output)


if __name__ == "__main__":
    raise SystemExit(_main())
