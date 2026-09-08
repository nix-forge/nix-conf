#!/usr/bin/env python3
"""Check Gecko text, emoji fallback, and web fonts using an isolated profile.

Requires selenium, Pillow, geckodriver, and an installed Zen or Firefox binary.
Run with --browser /path/to/zen-beta --output /tmp/font-rendering.
FONTCONFIG_FILE can select an isolated Fontconfig configuration for comparison.
"""

from __future__ import annotations

import argparse
import http.server
import io
import json
import math
import shutil
import socket
import string
import subprocess  # ruff: ignore[suspicious-subprocess-import] -- Starts only the explicitly selected local test browser.
import tempfile
import threading
import time
from pathlib import Path
from typing import TYPE_CHECKING
from urllib.parse import quote

if TYPE_CHECKING:
    from collections.abc import Callable

# Optional integration-test dependencies, supplied by the documented Nix command.
from PIL import Image
from selenium import webdriver
from selenium.webdriver.firefox.options import Options
from selenium.webdriver.firefox.service import Service

PIXEL_THRESHOLD = 100
MIN_PAINTED_PIXELS = 4

FAMILIES = [
    "Arial",
    "Roboto",
    "Inter",
    "Segoe UI",
    "system-ui",
    "sans-serif",
    "serif",
    "monospace",
]


def check_webfonts(driver: webdriver.Firefox, output: Path) -> bool:
    """Check third-party text and ligature fonts on an independent local page.

    Returns:
        Whether either font fails to load or icon names fail to form ligatures.

    """
    html = b"""<!doctype html><meta charset="utf-8">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Google+Sans+Flex:opsz,wght@6..144,1..1000&amp;display=swap">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Google+Symbols:opsz,wght,FILL,GRAD,ROND@48,100..300,0..1,0,100&amp;display=swap">
<style>body{background:#111;color:white;padding:32px;font:24px 'Google Sans Flex'}
.icon{font-family:'Google Symbols';font-size:64px;font-weight:200;font-feature-settings:'liga';margin:20px}</style>
<p>Third-party web font rendering: 0123456789</p>
<span class="icon">animation</span><span class="icon">zoom_enhance</span>
<span class="icon">factory</span><span class="icon">chevron_right</span>"""

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self) -> None:
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(html)

        def log_message(self, format: str, *args: object) -> None:  # ruff: ignore[builtin-argument-shadowing] -- Match the standard-library override, including keyword arguments.
            pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        driver.get(f"http://127.0.0.1:{server.server_port}/")
        results = driver.execute_async_script("""const done = arguments[0];
            Promise.all([
                ['Google Sans Flex', '400', '0123456789'],
                ['Google Symbols', '200', 'animation'],
            ].map(async ([family, weight, text]) => {
                try {
                    const faces = await document.fonts.load(`${weight} 64px "${family}"`, text);
                    const canvas = document.createElement('canvas');
                    const ctx = canvas.getContext('2d');
                    ctx.font = `${weight} 64px "${family}"`;
                    const width = ctx.measureText(text).width;
                    return {family, loaded: faces.length > 0, width,
                        ligature: family !== 'Google Symbols' || width <= 65};
                } catch (error) {
                    return {family, loaded: false, error: String(error)};
                }
            })).then(done);""")
        driver.save_screenshot(str(output / "webfonts.png"))
        (output / "webfonts.json").write_text(json.dumps(results, indent=2) + "\n")
        failed = any(not r["loaded"] or not r.get("ligature", False) for r in results)
        print(  # ruff: ignore[print] -- Diagnostic CLI verdict.
            f"{'FAIL' if failed else 'PASS'}: third-party text and icon web fonts"
        )
        return failed
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


def _configure_ublock(driver: webdriver.Firefox, xpi: Path, lists: list[str]) -> None:
    driver.install_addon(str(xpi.resolve()), temporary=True)
    driver.set_context("chrome")
    host = driver.execute_script("""return JSON.parse(Services.prefs.getStringPref(
        'extensions.webextensions.uuids'))['uBlock0@raymondhill.net'];""")
    driver.set_context("content")
    driver.get(f"moz-extension://{host}/dashboard.html")
    time.sleep(4)
    selected = driver.execute_async_script(
        """const lists = arguments[0], done = arguments[1];
        vAPI.messaging.send('dashboard', {
            what: 'applyFilterListSelection', toImport: lists.join('\\n'),
        }).then(() => vAPI.messaging.send('dashboard', {what: 'reloadAllFilters'}))
        .then(() => browser.storage.local.get('selectedFilterLists'))
        .then(done, error => done({error: String(error)}));""",
        lists,
    )
    if selected.get("error") or not set(lists).issubset(
        selected.get("selectedFilterLists", [])
    ):
        message = "uBlock did not apply the requested test filter lists"
        raise RuntimeError(message)


def check_multilingual(driver: webdriver.Firefox, output: Path) -> bool:
    """Check generic fallback against fonts with verified character coverage.

    Returns:
        Whether any sample fails to match a font that actually covers it.

    Raises:
        RuntimeError: Fontconfig is unavailable for discovering reference fonts.

    """
    fc_list = shutil.which("fc-list")
    if fc_list is None:
        message = "fc-list is required to discover script coverage"
        raise RuntimeError(message)
    samples = []
    for language, text in [("Telugu", "క"), ("Khmer", "ក"), ("Myanmar", "က")]:
        families = subprocess.check_output(  # ruff: ignore[subprocess-without-shell-equals-true] -- Fixed Fontconfig query, with no shell.
            [fc_list, "-f", "%{family[0]}\n", f":charset={ord(text):x}"], text=True
        )
        samples.append({
            "language": language,
            "text": text,
            "families": sorted(set(families.splitlines())),
        })
    driver.get("data:text/html;charset=utf-8,<meta charset=utf-8>")
    results = driver.execute_script(
        """return arguments[0].map(({language, text, families}) => {
        function render(font) {
            const canvas = document.createElement('canvas');
            canvas.width = 160; canvas.height = 120;
            const ctx = canvas.getContext('2d', {willReadFrequently:true});
            ctx.font = '48px ' + font; ctx.fillText(text, 20, 80);
            const data = ctx.getImageData(0, 0, 160, 120).data;
            const ink = [];
            for (let i = 3; i < data.length; i += 4) ink.push(data[i]);
            return {canvas, ink};
        }
        const generic = render('sans-serif');
        let best = null;
        for (const family of families) {
            const reference = render(JSON.stringify(family));
            const different = generic.ink.filter((p,i) => Math.abs(p-reference.ink[i]) > 20).length;
            if (!best || different < best.different) best = {family, reference, different};
            if (different === 0) break;
        }
        const label = document.createElement('p');
        label.textContent = language + ': ' + (best?.family || 'no installed coverage');
        document.body.append(label, generic.canvas);
        if (best) document.body.append(best.reference.canvas);
        return {language, matched_family: best?.family || null,
            different_pixels: best?.different ?? null,
            reference_ink: best?.reference.ink.filter(p => p > 20).length || 0,
            candidate_families: families};
    });""",
        samples,
    )
    (output / "multilingual.json").write_text(
        json.dumps(results, indent=2) + "\n", encoding="utf-8"
    )
    driver.save_screenshot(str(output / "multilingual.png"))
    failed = [
        r for r in results if r["different_pixels"] != 0 or not r["reference_ink"]
    ]
    print(  # ruff: ignore[print] -- Diagnostic CLI output.
        f"{'FAIL' if failed else 'PASS'}: {len(results) - len(failed)}/{len(results)} "
        "script fallbacks match fonts with verified character coverage"
    )
    return bool(failed)


def check_digits(driver: webdriver.Firefox, output: Path) -> bool:
    """Measure painted pixels for every test digit and save rendering evidence.

    Returns:
        Whether any digit failed to render.

    Raises:
        RuntimeError: A test row does not fit inside the captured viewport.

    """
    driver.set_window_size(1400, 1200)
    cases = [(f, v) for f in FAMILIES for v in ["normal", "tabular-nums"]]
    html = """<!doctype html><meta charset="utf-8"><style>
body { background: #111; color: white; font-size: 24px; }
.row { display: flex; height: 44px; }
label { font: 16px sans-serif; width: 280px; flex-shrink: 0; }
.digit { display: inline-block; min-width: 20px; height: 36px; }
</style>"""
    for index, (family, variant) in enumerate(cases):
        html += (
            f'<div class="row"><label>{family} {variant}</label>'
            f"<div style=\"font-family:'{family}';font-variant-numeric:{variant}\">"
        )
        html += "".join(
            f'<span class="digit" id="g{index}-{d}">{d}</span>' for d in string.digits
        )
        html += " 1080p HD 12:34 / 56:78</div></div>"
    html += (
        '<p style="font-family:sans-serif">Emoji and CJK: 😀 ❤️ 1️⃣ 日本語 中文 한국어</p>'
    )
    driver.get("data:text/html;charset=utf-8," + quote(html))
    driver.execute_async_script("document.fonts.ready.then(() => arguments[0]())")
    rectangles = driver.execute_script("""return [...document.querySelectorAll('.digit')].map(e => {
        const r = e.getBoundingClientRect();
        return {id: e.id, x: r.x, y: r.y, width: r.width, height: r.height};
    });""")
    png = driver.get_screenshot_as_png()
    (output / "rendering.png").write_bytes(png)
    screenshot = Image.open(io.BytesIO(png)).convert("RGB")
    viewport_width = driver.execute_script("return innerWidth")
    scale = screenshot.width / viewport_width
    results = []
    for rect in rectangles:
        box = (
            math.floor(rect["x"] * scale),
            math.floor(rect["y"] * scale),
            math.ceil((rect["x"] + rect["width"]) * scale),
            math.ceil((rect["y"] + rect["height"]) * scale),
        )
        if box[3] > screenshot.height:
            message = "Test row outside viewport; increase window size"
            raise RuntimeError(message)
        crop = screenshot.crop(box)
        painted = sum(p > PIXEL_THRESHOLD for p in crop.convert("L").tobytes())
        results.append({"id": rect["id"], "painted_pixels": painted})
    (output / "results.json").write_text(
        json.dumps(results, indent=2) + "\n", encoding="utf-8"
    )
    driver.set_context("chrome")
    graphics = driver.execute_async_script("""const done = arguments[0];
        ChromeUtils.importESModule('resource://gre/modules/Troubleshoot.sys.mjs')
            .Troubleshoot.snapshot().then(s => done(s.graphics));""")
    (output / "graphics.json").write_text(
        json.dumps(graphics, indent=2) + "\n", encoding="utf-8"
    )
    failures = [r for r in results if r["painted_pixels"] < MIN_PAINTED_PIXELS]
    print(  # ruff: ignore[print] -- The command reports its pass/fail result.
        f"{'FAIL' if failures else 'PASS'}: {len(results) - len(failures)}/{len(results)} "
        f"digits visible across {len(FAMILIES)} font families and two numeric styles"
    )
    return bool(failures)


def _wait_for_browser(browser: subprocess.Popen[bytes], port: int) -> None:
    """Wait until the isolated browser accepts Marionette connections.

    Raises:
        RuntimeError: The browser exits before accepting connections.
        TimeoutError: Marionette does not start within thirty seconds.

    """
    deadline = time.monotonic() + 30
    while True:
        if browser.poll() is not None:
            message = "Browser exited; inspect browser.log"
            raise RuntimeError(message)
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.5):
                break
        except OSError:
            if time.monotonic() >= deadline:
                message = "Marionette did not start; inspect browser.log"
                raise TimeoutError(message) from None
            time.sleep(0.1)


def main(
    *,
    digit_check: Callable[[webdriver.Firefox, Path], bool] = check_digits,
    argv: list[str] | None = None,
) -> bool:
    """Launch an isolated browser and report whether digits are visible.

    Returns:
        Whether any digit failed to render.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--browser", default=shutil.which("zen-beta") or shutil.which("firefox")
    )
    parser.add_argument("--geckodriver", default=shutil.which("geckodriver"))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--suite", choices=["digits", "multilingual", "webfonts"], default="digits"
    )
    parser.add_argument(
        "--ublock-xpi", type=Path, help="Install uBlock in the isolated test profile"
    )
    parser.add_argument(
        "--filter-list",
        action="append",
        default=[],
        help="Import a test uBlock filter list",
    )
    parser.add_argument("--generic-substitutions", type=int, default=127)
    parser.add_argument(
        "--headed", action="store_true", help="Also exercise the desktop compositor"
    )
    args = parser.parse_args(argv)
    if not args.browser or not args.geckodriver:
        parser.error("Provide --browser and --geckodriver, or put them on PATH")
    if args.filter_list and not args.ublock_xpi:
        parser.error("--filter-list requires --ublock-xpi")
    args.output.mkdir(parents=True, exist_ok=True)
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    prefs = {
        "marionette.port": port,
        "zen.welcome-screen.seen": True,
        "browser.startup.page": 0,
        "font.name.sans-serif.x-western": "Inter",
        "font.name.serif.x-western": "Literata",
        "font.name.monospace.x-western": "MonaspiceNe Nerd Font",
        "layout.css.devPixelsPerPx": "1.0",
        "gfx.font_rendering.fontconfig.max_generic_substitutions": args.generic_substitutions,
    }
    with tempfile.TemporaryDirectory(prefix="gecko-font-check-") as profile:
        Path(profile, "user.js").write_text(
            "\n".join(
                f"user_pref({json.dumps(k)}, {json.dumps(v)});"
                for k, v in prefs.items()
            ),
            encoding="utf-8",
        )
        command = [
            args.browser,
            "-no-remote",
            "-profile",
            profile,
            "-marionette",
            "--remote-allow-system-access",
        ]
        if not args.headed:
            command.append("-headless")
        with (args.output / "browser.log").open("w", encoding="utf-8") as log:
            browser = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)  # ruff: ignore[subprocess-without-shell-equals-true] -- No shell; the caller selects a local browser.
            driver = None
            try:
                _wait_for_browser(browser, port)
                # Connecting to the browser avoids geckodriver's Firefox-brand
                # binary validation, which rejects Zen's launcher.
                service = Service(
                    args.geckodriver,
                    service_args=[
                        "--connect-existing",
                        "--marionette-port",
                        str(port),
                    ],
                    log_output=str(args.output / "geckodriver.log"),
                )
                driver = webdriver.Firefox(options=Options(), service=service)
                if args.ublock_xpi:
                    _configure_ublock(driver, args.ublock_xpi, args.filter_list)
                check = {
                    "digits": digit_check,
                    "multilingual": check_multilingual,
                    "webfonts": check_webfonts,
                }[args.suite]
                return check(driver, args.output)
            finally:
                if driver is not None:
                    driver.quit()
                browser.terminate()
                try:
                    browser.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    browser.kill()
                    browser.wait()


if __name__ == "__main__":
    raise SystemExit(main())
