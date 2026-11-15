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
import sys
import tempfile
import time
from pathlib import Path

import websocket
from PIL import Image, ImageChops
from typescript_sources import javascript_source
from vscode.probe_process import owned_probe
from waits import FileChanges

INK_THRESHOLD = 35
MIN_ASPECT_RATIO = 0.7
DEVTOOLS_ENDPOINT_LINES = 2


class _CDP:
    def __init__(self, url: str, *, timeout: float = 15) -> None:
        self.ws = websocket.create_connection(
            url, suppress_origin=True, timeout=timeout
        )
        self.sequence = 0
        self.events: list[dict] = []

    def call(
        self, method: str, params: dict | None = None, *, timeout: float = 15
    ) -> dict:
        deadline = time.monotonic() + timeout
        self.ws.settimeout(timeout)
        self.sequence += 1
        self.ws.send(
            json.dumps({"id": self.sequence, "method": method, "params": params or {}})
        )
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError
            self.ws.settimeout(remaining)
            result = json.loads(self.ws.recv())
            if result.get("id") == self.sequence:
                if "error" in result:
                    raise RuntimeError(result["error"])
                return result.get("result", {})
            self.events.append(result)

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


def _page_endpoint(profile: Path) -> str:
    deadline = time.monotonic() + 30

    def remaining() -> float:
        duration = deadline - time.monotonic()
        if duration <= 0:
            raise TimeoutError
        return duration

    active = profile / "DevToolsActivePort"
    endpoint = ""

    def available() -> bool:
        nonlocal endpoint
        if not active.exists():
            return False
        lines = active.read_text().splitlines()
        if (
            len(lines) < DEVTOOLS_ENDPOINT_LINES
            or not lines[0].isdigit()
            or not lines[1].startswith("/devtools/browser/")
        ):
            return False
        endpoint = f"ws://127.0.0.1:{lines[0]}{lines[1]}"
        return True

    FileChanges(profile).wait(available, timeout=remaining())
    browser = _CDP(endpoint, timeout=remaining())
    try:
        browser.call(
            "Target.setDiscoverTargets", {"discover": True}, timeout=remaining()
        )
        targets = browser.call("Target.getTargets", timeout=remaining()).get(
            "targetInfos", []
        )
        while True:
            budget = remaining()
            page = next(
                (target for target in targets if target.get("type") == "page"), None
            )
            if page:
                host = endpoint.split("/devtools/", maxsplit=1)[0]
                return f"{host}/devtools/page/{page['targetId']}"
            if browser.events:
                event = browser.events.pop(0)
            else:
                browser.ws.settimeout(budget)
                event = json.loads(browser.ws.recv())
            target = event.get("params", {}).get("targetInfo")
            targets = [target] if isinstance(target, dict) else []
    finally:
        browser.ws.close()


class _ExecutionContexts:
    def __init__(self, frame_id: str) -> None:
        self.frame_id = frame_id
        self.current: dict | None = None
        self.generation = 0

    def accept(self, event: dict) -> None:
        params = event.get("params", {})
        method = event.get("method")
        context = params.get("context", {})
        if (
            method == "Runtime.executionContextCreated"
            and context.get("auxData", {}).get("isDefault")
            and context.get("auxData", {}).get("frameId") == self.frame_id
        ):
            self.current = context
            self.generation += 1
        elif method == "Runtime.executionContextsCleared" or (
            method == "Runtime.executionContextDestroyed"
            and self.current
            and params.get("executionContextId") == self.current["id"]
        ):
            self.current = None
            self.generation += 1

    def buffered(self, cdp: _CDP, deadline: float) -> None:
        while cdp.events:
            if time.monotonic() >= deadline:
                raise TimeoutError
            self.accept(cdp.events.pop(0))


def _wait_for_dom(cdp: _CDP, selector: str) -> None:
    deadline = time.monotonic() + 15

    def remaining() -> float:
        budget = deadline - time.monotonic()
        if budget <= 0:
            raise TimeoutError
        return budget

    observer = Path(__file__).resolve().parents[1] / "vscode" / "wait-for-dom.ts"
    frames = cdp.call("Page.getFrameTree", timeout=remaining())
    frame_id = frames["frameTree"]["frame"]["id"]
    contexts = _ExecutionContexts(frame_id)

    cdp.call("Runtime.disable", timeout=remaining())
    cdp.events.clear()
    cdp.call("Runtime.enable", timeout=remaining())
    contexts.buffered(cdp, deadline)
    while True:
        remaining()
        if contexts.current is None:
            cdp.ws.settimeout(remaining())
            contexts.accept(json.loads(cdp.ws.recv()))
            continue
        previous = contexts.generation
        try:
            result = cdp.call(
                "Runtime.callFunctionOn",
                {
                    "uniqueContextId": contexts.current["uniqueId"],
                    "functionDeclaration": javascript_source(observer),
                    "arguments": [
                        {"value": value}
                        for value in (selector, 1, None, remaining() * 1000)
                    ],
                    "awaitPromise": True,
                    "returnByValue": True,
                },
                timeout=remaining(),
            )
        except RuntimeError:
            contexts.buffered(cdp, deadline)
            if previous == contexts.generation:
                raise
            continue
        contexts.buffered(cdp, deadline)
        remaining()
        if previous != contexts.generation:
            continue
        if "exceptionDetails" in result:
            raise RuntimeError(result["exceptionDetails"])
        if result.get("result", {}).get("value") is not True:
            message = "DOM observer did not establish readiness"
            raise RuntimeError(message)
        return


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
        shutil.copyfile(Path(__file__).with_name("stopwatch-sample.sh"), sample)
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
        cdp = None
        env = os.environ.copy()
        # --noprofile/--norc do not disable BASH_ENV for a script shell.
        for name in ("BASH_ENV", "ENV"):
            env.pop(name, None)
        with owned_probe(
            root,
            [
                args.code,
                f"--user-data-dir={root / 'profile'}",
                f"--extensions-dir={root / 'extensions'}",
                "--disable-extensions",
                "--new-window",
                "--remote-debugging-port=0",
                str(workspace),
            ],
            env=env,
        ):
            try:
                cdp = _CDP(_page_endpoint(root / "profile"))
                _wait_for_dom(cdp, ".monaco-workbench")
                # Allow startup contributions and the diagnostic keybindings to load.
                time.sleep(5)
                cdp.evaluate(
                    "[...document.querySelectorAll('button, a, [role=button]')].find(e => e.textContent.trim() === 'Continue without Signing In')?.click()"
                )
                time.sleep(0.5)
                # Dispatch the terminal command once and observe its renderer.
                cdp.key("F6", 117)
                _wait_for_dom(cdp, ".xterm-screen canvas")
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
                try:
                    _close(cdp, args.output)
                finally:
                    shutil.copyfile(root / "code.log", args.output / "code.log")


if __name__ == "__main__":
    raise SystemExit(_main())
