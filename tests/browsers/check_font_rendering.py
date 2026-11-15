#!/usr/bin/env python3
"""Check Gecko text, emoji fallback, and web fonts using an isolated profile.

Requires fonttools, selenium, Pillow, geckodriver, and an installed Zen or
Firefox binary.
Run with --browser /path/to/zen-beta --output /tmp/font-rendering.
FONTCONFIG_FILE can select an isolated Fontconfig configuration for comparison.
"""

from __future__ import annotations

import argparse
import http.server
import io
import json
import math
import os
import re
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

from typescript_sources import javascript_source

if TYPE_CHECKING:
    from collections.abc import Callable

# Optional integration-test dependencies, supplied by the documented Nix command.
from fontTools.ttLib import TTFont
from fontTools.ttLib.ttFont import TTLibError
from notification_process import wait_child
from PIL import Image, ImageChops
from selenium import webdriver
from selenium.webdriver.firefox.options import Options
from selenium.webdriver.firefox.service import Service
from waits import FileChanges

PIXEL_THRESHOLD = 100
MIN_PAINTED_PIXELS = 4
MAX_PRIVATE_USE_PIXEL_DIFFERENCE = 500
MIN_EMOJI_COLORED_PIXELS = 100
MAX_TEXT_COLORED_PIXELS = 10
EMOJI_COLOR_SPREAD = 45
EMOJI_VISIBLE_CHANNEL = 70
# Representative legacy Apple private-use assignments carried by the provider.
# Keep this broader than U+F8FF so a provider update cannot silently regress the
# compatibility range while preserving the browser's normal named-family path.
PRIVATE_USE_CODEPOINTS = (0xF802, 0xF803, 0xF804, 0xF8FF)
APPLE_SYSTEM_STACK = (
    "-apple-system, BlinkMacSystemFont, SF Pro, SF Pro Icons, Helvetica Neue, "
    "Helvetica, Arial, Apple Color Emoji, sans-serif"
)
APPLE_WEB_STACK = "SF Pro, SF Pro Icons, Helvetica Neue, Helvetica, Arial, sans-serif"
APPLE_CHATGPT_STACK = (
    '-apple-system-body, ui-sans-serif, -apple-system, "system-ui", "Segoe UI", '
    'Helvetica, "Apple Color Emoji", Arial, "sans-serif", "Segoe UI Emoji", '
    '"Segoe UI Symbol"'
)
YOUTUBE_PLAYER_STACK = '"YouTube Noto", "Roboto", "Arial", "Helvetica", sans-serif'
APPLE_PLATFORM_FAMILIES = (
    "-apple-system",
    "-apple-system-body",
    "-apple-system-headline",
    "-apple-system-subheadline",
    "-apple-system-caption1",
    "-apple-system-caption2",
    "-apple-system-footnote",
    "-apple-system-short-body",
    "-apple-system-tall-body",
    "BlinkMacSystemFont",
)

FAMILIES = [
    "Arial",
    "Roboto",
    "Segoe UI",
    "system-ui",
    "sans-serif",
    "serif",
    "monospace",
]


def _html_fixture(fixture_name: str, /, **values: str) -> str:
    """Render a native HTML fixture without processing replacement text again.

    Returns:
        The fixture with each explicitly named value substituted once.

    """
    source = (
        (Path(__file__).with_name("fixtures") / fixture_name)
        .read_text(encoding="utf-8")
        .removesuffix("\n")
    )
    return re.sub(
        r"__([A-Za-z_][A-Za-z_0-9]*)__", lambda match: values[match[1]], source
    )


def _browser_program(name: str) -> str:
    """Load a checked browser function and pass the WebDriver arguments through.

    Returns:
        A script body with the same receiver, arguments, and completion callback.

    """
    source = javascript_source(Path(__file__).with_name("fixtures") / name)
    return (
        "const module = {exports: null};\n"
        + source
        + "\nreturn module.exports.apply(this, arguments);"
    )


def _fontconfig_query(pattern: str) -> str:
    """Make a simple family name unambiguous to Fontconfig's CLI parser.

    Fontconfig's textual pattern syntax treats ``-`` as a separator unless a
    family is supplied through the explicit ``family`` property. Browser APIs
    pass family names structurally, so mirror that boundary in CLI probes.

    Returns:
        A Fontconfig pattern that preserves the caller's intended structure.

    """
    if pattern.startswith(":") or ":" in pattern:
        return pattern
    return f":family={pattern}"


def _fontconfig_family(pattern: str) -> str:
    """Return the first family selected for a Fontconfig pattern.

    Returns:
        The selected family name.

    Raises:
        RuntimeError: Fontconfig is unavailable or returns an empty family.

    """
    fc_match = shutil.which("fc-match")
    if fc_match is None:
        message = "fc-match is required to discover browser font fixtures"
        raise RuntimeError(message)
    family = subprocess.check_output(  # ruff: ignore[subprocess-without-shell-equals-true]
        [fc_match, "-f", "%{family[0]}", _fontconfig_query(pattern)], text=True
    ).strip()
    if not family:
        message = f"Fontconfig returned an empty family for {pattern!r}"
        raise RuntimeError(message)
    return family


def _variable_font_metadata(path: Path) -> tuple[set[str], set[int]] | None:
    """Read the axis and character metadata needed by the variable fixture.

    Returns:
        The axis tags and cmap code points, or ``None`` for an unsupported face.

    """
    try:  # ruff: ignore[too-many-statements-in-try-clause] -- FontTools needs open, inspect, and close operations together.
        font = TTFont(path, lazy=True)
        try:
            axes = {axis.axisTag for axis in font["fvar"].axes}
            cmap = set((font.getBestCmap() or {}).keys())
        finally:
            font.close()
    except OSError, KeyError, TTLibError, ValueError:
        return None
    return axes, cmap


def _variable_font_file(sample: str) -> Path:
    """Find a variable font with the axes and glyphs used by the matrix.

    Returns:
        A font file containing ``wght`` and ``wdth`` axes and the sample glyphs.

    Raises:
        RuntimeError: Fontconfig is unavailable or no suitable font is found.

    """
    fc_list = shutil.which("fc-list")
    if fc_list is None:
        message = "fc-list is required to discover a variable browser fixture"
        raise RuntimeError(message)
    paths = dict.fromkeys(
        Path(raw).resolve()
        for raw in subprocess.check_output(  # ruff: ignore[subprocess-without-shell-equals-true]
            [fc_list, "-f", "%{file}\n"], text=True
        ).splitlines()
    )
    for path in paths:
        if not path.is_file():
            continue
        metadata = _variable_font_metadata(path)
        if metadata is None:
            continue
        axes, cmap = metadata
        if {"wght", "wdth"}.issubset(axes) and all(
            ord(character) in cmap for character in sample if character != " "
        ):
            return path
    message = "Fontconfig did not expose a variable font with wght and wdth axes"
    raise RuntimeError(message)


def _css_family(family: str) -> str:
    """Quote a Fontconfig family name for a CSS declaration.

    Returns:
        A CSS string literal containing the family name.

    """
    return json.dumps(family)


def _private_use_fallback_family() -> str:
    """Discover the configured provider for a named stack's legacy PUA glyph.

    Returns:
        The selected fallback family name.

    """
    return _fontconfig_family(":family=Roboto:charset=F8FF")


def _fontconfig_role_families() -> tuple[str, str, str]:
    """Discover the active sans, serif, and monospace role families.

    Returns:
        The configured sans, serif, and monospace family names.

    """
    return (
        _fontconfig_family("sans-serif"),
        _fontconfig_family("serif"),
        _fontconfig_family("monospace"),
    )


def _fontconfig_file(pattern: str, expected_family: str) -> Path:
    """Resolve one installed face through the active isolated Fontconfig.

    Returns:
        The resolved path to the selected face.

    Raises:
        RuntimeError: Fontconfig is unavailable or returns a missing file.

    """
    fc_match = shutil.which("fc-match")
    if fc_match is None:
        message = "fc-match is required to discover browser font fixtures"
        raise RuntimeError(message)
    family, raw_path = (
        subprocess  # ruff: ignore[subprocess-without-shell-equals-true]
        .check_output(
            [fc_match, "-f", "%{family[0]}\t%{file}", _fontconfig_query(pattern)],
            text=True,
        )
        .strip()
        .split("\t", 1)
    )
    if family != expected_family:
        message = f"Fontconfig selected {family!r}, expected {expected_family!r}"
        raise RuntimeError(message)
    path = Path(raw_path).resolve()
    if not path.is_file():
        message = f"Fontconfig returned a missing browser font fixture: {path}"
        raise RuntimeError(message)
    return path


def _fontconfig_postscript_name(pattern: str) -> str:
    """Return a face's PostScript name for a CSS ``local()`` test.

    Returns:
        The selected face's PostScript name.

    Raises:
        RuntimeError: Fontconfig is unavailable.

    """
    fc_match = shutil.which("fc-match")
    if fc_match is None:
        message = "fc-match is required to discover browser font fixtures"
        raise RuntimeError(message)
    return subprocess.check_output(  # ruff: ignore[subprocess-without-shell-equals-true]
        [fc_match, "-f", "%{postscriptname}", _fontconfig_query(pattern)], text=True
    ).strip()


def check_font_compatibility(  # ruff: ignore[complex-structure,too-many-branches,too-many-locals,too-many-statements] -- Keep the browser matrix and its evidence together.
    driver: webdriver.Firefox, output: Path
) -> bool:
    """Exercise local, installed, generic, variable, and shaped web fonts.

    The fixture is served entirely from loopback. It deliberately uses a
    downloaded face under the configured sans role name on one page, then removes the
    page-owned ``@font-face`` on the next page, proving that web-font shadowing
    is document-scoped and cannot leak into the installed role. The rest of
    the matrix checks ``local()`` full/PostScript names, style faces, variable
    variation settings, generic UI roles, monospace advances, layout metrics,
    and representative emoji clusters.

    Returns:
        Whether any browser compatibility invariant failed.

    """
    sample = "The quick brown fox jumps over 0123456789"
    sans_family, serif_family, monospace_family = _fontconfig_role_families()
    regular = _fontconfig_file(":family=Roboto:style=Regular", "Roboto")
    bold = _fontconfig_file(":family=Roboto:style=Bold", "Roboto")
    italic = _fontconfig_file(":family=Roboto:style=Italic", "Roboto")
    variable = _variable_font_file(sample)
    postscript = _fontconfig_postscript_name(":family=Roboto:style=Regular")
    sans_css = _css_family(sans_family)
    serif_css = _css_family(serif_family)
    monospace_css = _css_family(monospace_family)
    sans_descriptor = f"400 40px {sans_css}"
    font_files = {
        "/regular.ttf": regular,
        "/bold.ttf": bold,
        "/italic.ttf": italic,
        "/variable.ttf": variable,
        "/shadow.ttf": regular,
    }
    pages = {
        "/installed.html": _html_fixture(
            "installed.html.in", sans_css=f"{sans_css}", sample=f"{sample}"
        ).encode(),
        "/shadow.html": _html_fixture(
            "shadow.html.in", sans_css=f"{sans_css}", sample=f"{sample}"
        ).encode(),
        "/local.html": _html_fixture(
            "local.html.in", postscript=f"{postscript}", sample=f"{sample}"
        ).encode(),
        "/faces.html": _html_fixture(
            "faces.html.in",
            sample=f"{sample}",
            sans_css=f"{sans_css}",
            serif_css=f"{serif_css}",
            monospace_css=f"{monospace_css}",
        ).encode(),
    }

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self) -> None:
            path = self.path.split("?", 1)[0]
            if path in font_files:
                data = font_files[path].read_bytes()
                self.send_response(200)
                self.send_header("Content-Type", "font/ttf")
                self.send_header("Cache-Control", "no-store")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return
            data = pages.get(path)
            if data is None:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def log_message(self, format: str, *args: object) -> None:  # ruff: ignore[builtin-argument-shadowing] -- Match the standard-library override.
            pass

    def metrics(driver: webdriver.Firefox, identifier: str) -> dict:
        return driver.execute_script(
            _browser_program("font-element-metrics.cts"),
            identifier,
        )

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    results: dict = {
        "fixtures": {name: str(path) for name, path in font_files.items()},
        "postscript": postscript,
    }
    try:
        driver.set_window_size(1600, 1200)
        base = f"http://127.0.0.1:{server.server_port}"

        driver.get(base + "/installed.html")
        installed = metrics(driver, "sample")
        driver.save_screenshot(str(output / "font-compatibility-installed.png"))

        driver.get(base + "/shadow.html")
        shadow_loaded = driver.execute_async_script(
            _browser_program("font-descriptor-load.cts"),
            sample,
            sans_descriptor,
        )
        shadow = metrics(driver, "sample")
        driver.save_screenshot(str(output / "font-compatibility-shadow.png"))

        driver.get(base + "/installed.html")
        installed_after_shadow = metrics(driver, "sample")

        driver.get(base + "/local.html")
        local = driver.execute_async_script(
            _browser_program("local-font-name-load.cts"),
            sample,
        )
        local_metrics = {
            identifier: metrics(driver, identifier)
            for identifier in ("full", "postscript", "reference")
        }
        driver.save_screenshot(str(output / "font-compatibility-local.png"))

        driver.get(base + "/faces.html")
        face_result = driver.execute_async_script(
            _browser_program("font-compatibility-metrics.cts"),
            sample,
            monospace_family,
        )
        driver.save_screenshot(str(output / "font-compatibility-faces.png"))
        results.update({
            "installed": installed,
            "installedAfterShadow": installed_after_shadow,
            "shadow": {"load": shadow_loaded, "metrics": shadow},
            "local": {"load": local, "metrics": local_metrics},
            "faces": face_result,
        })
    finally:
        server.shutdown()
        server.server_close()
        thread.join()

    failures = []
    if not shadow_loaded["loaded"] or not shadow_loaded["checked"]:
        failures.append("downloaded web font did not load")
    if abs(shadow["textWidth"] - installed["textWidth"]) <= 1.0:
        failures.append("same-name web font did not shadow the installed face")
    if abs(installed_after_shadow["textWidth"] - installed["textWidth"]) > 1.0:
        failures.append("web-font shadow leaked beyond its document")
    if (
        not local["full"]
        or not local["postscript"]
        or not all(local[key] for key in ("fullChecked", "postscriptChecked"))
    ):
        failures.append("local() full or PostScript name did not load")
    reference_width = local_metrics["reference"]["textWidth"]
    failures.extend(
        f"local() {identifier} metrics differ from installed face"
        for identifier in ("full", "postscript")
        if abs(local_metrics[identifier]["textWidth"] - reference_width) > 1.0
    )
    declared_faces = ("regular", "bold", "italic", "variable")
    if not all(face_result["loaded"][name] for name in declared_faces) or not all(
        face_result["checked"][name] for name in declared_faces
    ):
        failures.append("one or more declared style or variable faces did not load")
    face_metrics = face_result["metrics"]
    if (
        face_metrics["italic"]["fontStyle"] != "italic"
        or face_metrics["bold"]["fontWeight"] != "700"
    ):
        failures.append("CSS style descriptors were not preserved")
    variable_low = face_result["variableCanvas"]["low"]
    variable_high = face_result["variableCanvas"]["high"]
    if (
        abs(
            face_metrics["variable-low"]["width"]
            - face_metrics["variable-high"]["width"]
        )
        <= 1.0
    ):
        failures.append("variable font width axis did not change measured advances")
    if min(variable_low["ink"], variable_high["ink"]) < MIN_PAINTED_PIXELS:
        failures.append("variable font weight samples did not paint glyphs")
    elif variable_low["ink"] == variable_high["ink"]:
        failures.append("variable font weight axis did not change painted glyphs")
    mono = face_result["monoCanvas"]
    if abs(mono["lower"]["width"] - mono["upper"]["width"]) > 1.0:
        failures.append("configured monospace face has unequal cell advances")
    generic_roles = {
        "generic-system": "role-sans",
        "generic-sans": "role-sans",
        "generic-ui-sans": "role-sans",
        "generic-ui-serif": "role-serif",
        "generic-ui-mono": "role-mono",
        "generic-ui-rounded": "role-sans",
    }
    for generic, role in generic_roles.items():
        if abs(face_metrics[generic]["width"] - face_metrics[role]["width"]) > 1.0:
            failures.append(
                f"CSS generic {generic} differs from configured {role} role"
            )
    if face_metrics["wrap"]["height"] <= face_metrics["wrap"]["lineHeight"]:
        failures.append("fixed-width text did not wrap into multiple line boxes")
    emoji_failures = {
        name: value
        for name, value in face_result["emoji"].items()
        if value["ink"] < MIN_PAINTED_PIXELS or value["clusters"] != 1
    }
    if emoji_failures:
        failures.append(f"emoji cluster rendering failed: {sorted(emoji_failures)}")
    failed = bool(failures)
    results["failures"] = failures
    results["passed"] = not failed
    (output / "font-compatibility.json").write_text(
        json.dumps(results, indent=2) + "\n", encoding="utf-8"
    )
    print(  # ruff: ignore[print] -- The command reports the test verdict.
        f"{'FAIL' if failed else 'PASS'}: local/web/generic/style/variable/emoji font matrix"
    )
    if failures:
        print(json.dumps(failures, indent=2))  # ruff: ignore[print] -- Diagnostic CLI output.
    return failed


def check_emoji_presentation(driver: webdriver.Firefox, output: Path) -> bool:
    """Verify Unicode emoji defaults without overriding explicit text choices.

    Returns:
        Whether the rendered presentation differs from the requested style.

    """
    samples = {
        "emoji-default": ("😄", ""),
        "text-default": ("☺", ""),
        "requested-emoji": ("☺️", ""),
        "requested-text": ("☺︎", ""),
        "author-text": ("😄", "font-variant-emoji:text"),
    }
    rows = "".join(
        _html_fixture(
            "emoji-row.html.in", name=f"{name}", style=f"{style}", glyph=f"{glyph}"
        )
        for name, (glyph, style) in samples.items()
    )
    html = _html_fixture("emoji-presentation.html.in", rows=f"{rows}").encode()

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self) -> None:
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(html)

        def log_message(self, format: str, *args: object) -> None:  # ruff: ignore[builtin-argument-shadowing] -- Match the standard-library override.
            pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        driver.set_window_size(320, 700)
        driver.get(f"http://127.0.0.1:{server.server_port}/")
        driver.execute_async_script("document.fonts.ready.then(() => arguments[0]())")
        pixels = {}
        for name in samples:
            screenshot = driver.find_element("id", name).screenshot_as_png
            bitmap = Image.open(io.BytesIO(screenshot)).convert("RGB")
            pixels[name] = sum(
                max(rgb) - min(rgb) > EMOJI_COLOR_SPREAD
                and max(rgb) > EMOJI_VISIBLE_CHANNEL
                for rgb in bitmap.get_flattened_data()
                if isinstance(rgb, tuple)
            )
    finally:
        server.shutdown()
        server.server_close()
        thread.join()

    failures = [
        name
        for name in ("emoji-default", "requested-emoji")
        if pixels[name] < MIN_EMOJI_COLORED_PIXELS
    ] + [
        name
        for name in ("text-default", "requested-text", "author-text")
        if pixels[name] > MAX_TEXT_COLORED_PIXELS
    ]
    (output / "emoji-presentation.json").write_text(
        json.dumps({"colored_pixels": pixels, "failures": failures}, indent=2) + "\n",
        encoding="utf-8",
    )
    print(  # ruff: ignore[print] -- The command reports the browser test verdict.
        f"{'FAIL' if failures else 'PASS'}: Unicode emoji presentation and text overrides"
    )
    return bool(failures)


def check_webfonts(driver: webdriver.Firefox, output: Path) -> bool:
    """Check third-party text and ligature fonts on an independent local page.

    Returns:
        Whether either font fails to load or icon names fail to form ligatures.

    """
    html = (Path(__file__).with_name("fixtures") / "webfonts.html").read_bytes()

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
        results = driver.execute_async_script(
            _browser_program("webfont-load-and-ligatures.cts")
        )
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
    host = driver.execute_script(_browser_program("ublock-extension-host.cts"))
    driver.set_context("content")
    driver.get(f"moz-extension://{host}/dashboard.html")
    time.sleep(4)
    selected = driver.execute_async_script(
        _browser_program("ublock-filter-list-selection.cts"),
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
    script_samples = [
        ("Japanese", "日本語かな"),
        ("Simplified Chinese", "汉字中文"),
        ("Traditional Chinese", "漢字繁體"),
        ("Korean", "한글테스트"),
        ("Arabic", "العَرَبِيّة"),
        ("Hebrew", "עִבְרִית"),
        ("Devanagari", "नमस्ते"),
        ("Thai", "ภาษาไทย"),
        ("Telugu", "తెలుగు"),
        ("Khmer", "ភាសាខ្មែរ"),
        ("Myanmar", "မြန်မာ"),
    ]
    for language, text in script_samples:
        charset = ",".join(f"{ord(character):x}" for character in text)
        families = subprocess.check_output(  # ruff: ignore[subprocess-without-shell-equals-true] -- Fixed Fontconfig query, with no shell.
            [fc_list, "-f", "%{family[0]}\n", f":charset={charset}"], text=True
        )
        samples.append({
            "language": language,
            "text": text,
            "families": sorted(set(families.splitlines())),
        })
    driver.get("data:text/html;charset=utf-8,<meta charset=utf-8>")
    results = driver.execute_script(
        _browser_program("multilingual-fallback-comparison.cts"),
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
    html = _html_fixture("numeric-header.html.in")
    for index, (family, variant) in enumerate(cases):
        html += _html_fixture(
            "numeric-row.html.in", family=f"{family}", variant=f"{variant}"
        )
        html += "".join(
            _html_fixture("numeric-digit.html.in", index=f"{index}", d=f"{d}")
            for d in string.digits
        )
        html += " 1080p HD 12:34 / 56:78</div></div>"
    html += (
        '<p style="font-family:sans-serif">Emoji and CJK: 😀 ❤️ 1️⃣ 日本語 中文 한국어</p>'
    )
    driver.get("data:text/html;charset=utf-8," + quote(html))
    driver.execute_async_script("document.fonts.ready.then(() => arguments[0]())")
    rectangles = driver.execute_script(_browser_program("numeric-digit-rectangles.cts"))
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
    graphics = driver.execute_async_script(
        _browser_program("firefox-graphics-snapshot.cts")
    )
    (output / "graphics.json").write_text(
        json.dumps(graphics, indent=2) + "\n", encoding="utf-8"
    )
    failures = [r for r in results if r["painted_pixels"] < MIN_PAINTED_PIXELS]
    print(  # ruff: ignore[print] -- The command reports its pass/fail result.
        f"{'FAIL' if failures else 'PASS'}: {len(results) - len(failures)}/{len(results)} "
        f"digits visible across {len(FAMILIES)} font families and two numeric styles"
    )
    return bool(failures)


def check_private_use(  # ruff: ignore[too-many-locals] -- Keep the three-way PUA evidence together.
    driver: webdriver.Firefox, output: Path
) -> bool:
    """Check named-stack PUA fallback and the generic-only negative control.

    Returns:
        Whether any private-use glyph failed its named-stack or generic-only
        compatibility contract.

    """
    fallback_family = _private_use_fallback_family()
    driver.set_window_size(1200, 640)
    rows = "".join(
        _html_fixture(
            "private-use-row.html.in",
            codepoint_f_04X=f"{codepoint:04X}",
            codepoint_f_x=f"{codepoint:x}",
            chr_codepoint=f"{chr(codepoint)}",
            css_family_fallback_family=f"{_css_family(fallback_family)}",
        )
        for codepoint in PRIVATE_USE_CODEPOINTS
    )
    html = _html_fixture("private-use.html.in", rows=f"{rows}")
    driver.get("data:text/html;charset=utf-8," + quote(html))
    driver.execute_async_script("document.fonts.ready.then(() => arguments[0]())")

    results = []
    for codepoint in PRIVATE_USE_CODEPOINTS:
        target = driver.find_element("id", f"target-{codepoint:x}")
        reference = driver.find_element("id", f"reference-{codepoint:x}")
        target_image = Image.open(io.BytesIO(target.screenshot_as_png)).convert("RGB")
        reference_image = Image.open(io.BytesIO(reference.screenshot_as_png)).convert(
            "RGB"
        )
        generic = driver.find_element("id", f"generic-{codepoint:x}")
        generic_image = Image.open(io.BytesIO(generic.screenshot_as_png)).convert("RGB")
        target_image.save(output / f"private-use-target-u-{codepoint:04x}.png")
        reference_image.save(output / f"private-use-reference-u-{codepoint:04x}.png")
        generic_image.save(output / f"private-use-generic-u-{codepoint:04x}.png")

        target_rect = driver.execute_script(
            "return arguments[0].getBoundingClientRect().toJSON()", target
        )
        reference_rect = driver.execute_script(
            "return arguments[0].getBoundingClientRect().toJSON()", reference
        )
        same_size = target_image.size == reference_image.size
        generic_same_size = generic_image.size == reference_image.size
        different_pixels = None
        generic_different_pixels = None
        if same_size:
            difference = ImageChops.difference(target_image, reference_image)
            difference_bytes = difference.tobytes()
            different_pixels = sum(
                any(difference_bytes[offset : offset + 3])
                for offset in range(0, len(difference_bytes), 3)
            )
        if generic_same_size:
            difference = ImageChops.difference(generic_image, reference_image)
            difference_bytes = difference.tobytes()
            generic_different_pixels = sum(
                any(difference_bytes[offset : offset + 3])
                for offset in range(0, len(difference_bytes), 3)
            )
        target_ink = sum(
            pixel > PIXEL_THRESHOLD for pixel in target_image.convert("L").tobytes()
        )
        results.append({
            "codepoint": f"U+{codepoint:04X}",
            "target": target_rect,
            "reference": reference_rect,
            "target_image_size": target_image.size,
            "reference_image_size": reference_image.size,
            "generic_image_size": generic_image.size,
            "target_ink_pixels": target_ink,
            "different_pixels": different_pixels,
            "generic_different_pixels": generic_different_pixels,
            "generic_does_not_use_named_fallback": (
                not generic_same_size
                or (
                    generic_different_pixels is not None
                    and generic_different_pixels > MAX_PRIVATE_USE_PIXEL_DIFFERENCE
                )
            ),
            "failed": (
                not same_size
                or target_ink < MIN_PAINTED_PIXELS
                or (
                    different_pixels is not None
                    and different_pixels > MAX_PRIVATE_USE_PIXEL_DIFFERENCE
                )
                or (
                    generic_same_size
                    and (
                        generic_different_pixels is None
                        or generic_different_pixels <= MAX_PRIVATE_USE_PIXEL_DIFFERENCE
                    )
                )
            ),
        })
    failures = [result for result in results if result["failed"]]
    (output / "private-use.json").write_text(
        json.dumps(
            {
                "fallback_family": fallback_family,
                "codepoints": [
                    f"U+{codepoint:04X}" for codepoint in PRIVATE_USE_CODEPOINTS
                ],
                "results": results,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    driver.save_screenshot(str(output / "private-use.png"))

    print(  # ruff: ignore[print] -- The command reports its pass/fail result.
        f"{'FAIL' if failures else 'PASS'}: "
        f"{len(results) - len(failures)}/{len(results)} named-family PUA cases and "
        "generic-only negative controls"
    )
    return bool(failures)


def check_apple_system_stack(  # ruff: ignore[too-many-locals] -- Keep the complete browser fixture and evidence together.
    driver: webdriver.Firefox, output: Path
) -> bool:
    """Ensure the compatibility provider does not hijack an Apple web stack.

    The local web font deliberately uses Roboto's bytes under an Apple web
    family name. This keeps the test offline while exercising the same browser
    decision boundary as Apple's stylesheet: a web font appears in the named
    portion of the platform stack, and a private-use character must remain
    visible. The exact platform stack is also rendered. Generic-only requests
    are included as a second boundary because they should remain controlled by
    the browser's configured Stylix roles.

    Returns:
        Whether ordinary text was changed to the compatibility provider or the
        private-use fallback stopped working.

    Raises:
        RuntimeError: The test font cannot be discovered through Fontconfig.

    """
    fc_match = shutil.which("fc-match")
    if fc_match is None:
        message = "fc-match is required to serve the offline web-font fixture"
        raise RuntimeError(message)
    generic_families = (
        "sans-serif",
        "system-ui",
        "ui-sans-serif",
        "ui-serif",
        "ui-monospace",
        "ui-rounded",
        "serif",
        "monospace",
    )
    generic_matches = {
        family: subprocess.check_output(  # ruff: ignore[subprocess-without-shell-equals-true]
            [fc_match, "-f", "%{family[0]}", _fontconfig_query(family)], text=True
        ).strip()
        for family in generic_families
    }
    web_font = Path(
        subprocess.check_output(  # ruff: ignore[subprocess-without-shell-equals-true]
            [fc_match, "-f", "%{file}", "Roboto:style=Regular"], text=True
        ).strip()
    )
    configured_sans_family = _fontconfig_family("sans-serif")
    configured_serif_family = _fontconfig_family("serif")
    configured_monospace_family = _fontconfig_family("monospace")
    apple_web_font = Path(
        subprocess.check_output(  # ruff: ignore[subprocess-without-shell-equals-true]
            [fc_match, "-f", "%{file}", "SF Pro:style=Regular"], text=True
        ).strip()
    )
    fallback_family = _private_use_fallback_family()
    if not web_font.is_file() or not apple_web_font.is_file():
        message = f"Fontconfig returned a missing web-font fixture: {web_font}"
        raise RuntimeError(message)

    sample = "Habi App Habit Tracker & Focus Timer"
    private_use = chr(0xF8FF)
    html = _html_fixture(
        "apple-web.html.in",
        APPLE_SYSTEM_STACK=f"{APPLE_SYSTEM_STACK}",
        sample=f"{sample}",
        APPLE_WEB_STACK=f"{APPLE_WEB_STACK}",
        css_family_fallback_family=f"{_css_family(fallback_family)}",
        private_use=f"{private_use}",
    ).encode()

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self) -> None:
            if self.path == "/apple-web-test.ttf":
                data = web_font.read_bytes()
                self.send_response(200)
                self.send_header("Content-Type", "font/ttf")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return
            if self.path == "/role-local.ttf":
                data = apple_web_font.read_bytes()
                self.send_response(200)
                self.send_header("Content-Type", "font/ttf")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(html)

        def log_message(self, format: str, *args: object) -> None:  # ruff: ignore[builtin-argument-shadowing]
            pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        driver.set_window_size(1400, 600)
        driver.get(f"http://127.0.0.1:{server.server_port}/")
        driver.execute_async_script(
            _browser_program("apple-system-stack-font-load.cts"),
            sample,
            private_use,
        )
        result = driver.execute_script(
            _browser_program("apple-system-stack-metrics.cts")
        )
        driver.save_screenshot(str(output / "apple-system-stack.png"))
    finally:
        server.shutdown()
        server.server_close()
        thread.join()

    widths = result["widths"]
    ordinary_not_hijacked = (
        abs(widths["named-stack"] - widths["fallback"]) > 1.0
        and widths["named-stack"] > 0
    )
    platform_stack_preserves_web_font = (
        abs(widths["stack"] - widths["web"]) <= 1.0 and widths["stack"] > 0
    )
    generic_not_hijacked = all(
        abs(widths[family] - widths["fallback"]) > 1.0 and widths[family] > 0
        for family in ("system-ui", "sans-serif")
    )
    generic_fontconfig_not_hijacked = all(
        family != fallback_family for family in generic_matches.values()
    )
    generic_roles_preserved = generic_matches == {
        "sans-serif": configured_sans_family,
        "system-ui": configured_sans_family,
        "ui-sans-serif": configured_sans_family,
        "ui-serif": configured_serif_family,
        "ui-monospace": configured_monospace_family,
        "ui-rounded": configured_sans_family,
        "serif": configured_serif_family,
        "monospace": configured_monospace_family,
    }
    private_use_preserved = widths["private-stack"] > 0 and any(
        abs(widths["private-stack"] - widths[reference]) <= 1.0
        and widths[reference] > 0
        for reference in ("private-system", "private-reference")
    )
    failed = (
        not result["webFontLoaded"]
        or not ordinary_not_hijacked
        or not platform_stack_preserves_web_font
        or not generic_not_hijacked
        or not generic_fontconfig_not_hijacked
        or not generic_roles_preserved
        or not private_use_preserved
    )
    (output / "apple-system-stack.json").write_text(
        json.dumps(
            {
                "web_font": str(web_font),
                "configured_sans_family": configured_sans_family,
                "apple_web_font": str(apple_web_font),
                "stack": APPLE_SYSTEM_STACK,
                "fallback_family": fallback_family,
                "generic_matches": generic_matches,
                "generic_roles_preserved": generic_roles_preserved,
                "ordinary_not_hijacked": ordinary_not_hijacked,
                "generic_not_hijacked": generic_not_hijacked,
                "generic_fontconfig_not_hijacked": generic_fontconfig_not_hijacked,
                "private_use_preserved": private_use_preserved,
                "result": result,
                "platform_stack_preserves_web_font": platform_stack_preserves_web_font,
                "failed": failed,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(  # ruff: ignore[print] -- The command reports its pass/fail result.
        f"{'FAIL' if failed else 'PASS'}: Apple-style web-font stack preserves ordinary text "
        "and a visible private-use glyph"
    )
    return failed


def check_apple_platform_namespace(  # ruff: ignore[too-many-locals] -- Keep matching and browser evidence together.
    driver: webdriver.Firefox, output: Path
) -> bool:
    """Ensure Apple CSS platform names do not steal later CSS families.

    These names are CSS protocol identifiers implemented natively by Apple's
    text stack. On Linux they should remain unresolved until the browser can
    try the page's later named families or its final generic family. Resolving
    them to the private-use compatibility provider would recreate the Lucida
    Grande regression, while resolving them to a local UI role would hide a
    page-provided SF Pro web font.

    Returns:
        Whether any platform alias resolves to the private-use provider or
        renders as an empty browser result.

    Raises:
        RuntimeError: Fontconfig is unavailable or the configured role is not
            installed.

    """
    fc_match = shutil.which("fc-match")
    if fc_match is None:
        message = "fc-match is required to verify Apple platform names"
        raise RuntimeError(message)

    family_matches = {
        family: subprocess.check_output(  # ruff: ignore[subprocess-without-shell-equals-true]
            [fc_match, "-f", "%{family[0]}", f":family={family}"], text=True
        ).strip()
        for family in APPLE_PLATFORM_FAMILIES
    }
    if any(not match for match in family_matches.values()):
        message = "Fontconfig returned an empty family for an Apple platform name"
        raise RuntimeError(message)

    configured_sans_family = _fontconfig_family("sans-serif")
    fallback_family = _private_use_fallback_family()
    sample = "ChatGPT Habi is a daily habit tracker"
    browser_cases = {
        "configured-sans": _css_family(configured_sans_family),
        "fallback": _css_family(fallback_family),
        **{
            f"family-{index}": json.dumps(family)
            for index, family in enumerate(APPLE_PLATFORM_FAMILIES)
        },
        "apple-stack": APPLE_SYSTEM_STACK,
        "chatgpt-stack": APPLE_CHATGPT_STACK,
    }
    rows = "".join(
        _html_fixture(
            "apple-platform-row.html.in",
            identifier=f"{identifier}",
            family=f"{family}",
            sample=f"{sample}",
        )
        for identifier, family in browser_cases.items()
    )
    html = _html_fixture("apple-platform.html.in", rows=f"{rows}").encode()

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self) -> None:
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(html)

        def log_message(self, format: str, *args: object) -> None:  # ruff: ignore[builtin-argument-shadowing]
            pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        driver.set_window_size(1600, 900)
        driver.get(f"http://127.0.0.1:{server.server_port}/")
        driver.execute_async_script("document.fonts.ready.then(() => arguments[0]())")
        result = driver.execute_script(
            _browser_program("apple-platform-namespace-metrics.cts"),
            browser_cases,
        )
        driver.save_screenshot(str(output / "apple-platform-namespace.png"))
    finally:
        server.shutdown()
        server.server_close()
        thread.join()

    metrics = result["metrics"]
    fallback_width = metrics["fallback"]["width"]
    browser_aliases = [
        *(f"family-{index}" for index in range(len(APPLE_PLATFORM_FAMILIES))),
        "chatgpt-stack",
    ]
    browser_failures = [
        identifier
        for identifier in browser_aliases
        if metrics[identifier]["width"] <= 0
        or abs(metrics[identifier]["width"] - fallback_width) <= 1.0
    ]
    failed = (
        any(match == fallback_family for match in family_matches.values())
        or not result["configuredSansAvailable"]
        or bool(browser_failures)
    )
    (output / "apple-platform-namespace.json").write_text(
        json.dumps(
            {
                "families": list(APPLE_PLATFORM_FAMILIES),
                "configured_sans_family": configured_sans_family,
                "fallback_family": fallback_family,
                "family_matches": family_matches,
                "stack": APPLE_SYSTEM_STACK,
                "chatgpt_stack": APPLE_CHATGPT_STACK,
                "result": result,
                "browser_failures": browser_failures,
                "failed": failed,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(  # ruff: ignore[print] -- The command reports the pass/fail result.
        f"{'FAIL' if failed else 'PASS'}: Apple platform names preserve later CSS families "
        "without selecting the private-use provider"
    )
    return failed


def check_missing_named_stack(driver: webdriver.Firefox, output: Path) -> bool:
    """Ensure an unavailable first family does not steal later CSS families.

    A Fontconfig compatibility provider for a private-use glyph must not become
    the ordinary-text result for an unavailable family. YouTube's player uses
    ``YouTube Noto`` before ``Roboto``; the second case is a synthetic missing
    family to keep this regression general instead of encoding a site fix.

    Returns:
        Whether either stack selected the private-use compatibility provider for
        ordinary text instead of reaching the installed Roboto role.

    """
    fallback_family = _private_use_fallback_family()
    missing_families = ("YouTube Noto", "Unavailable Web Family")
    configured_sans_family = _fontconfig_family("sans-serif")
    sample = "In this video 0:01 / 8:57"
    stacks = {
        "youtube": YOUTUBE_PLAYER_STACK,
        "synthetic": f'"{missing_families[1]}", "Roboto", "Arial", sans-serif',
    }
    html = _html_fixture(
        "youtube-synthetic-bold.html.in",
        sample=f"{sample}",
        css_family_fallback_family=f"{_css_family(fallback_family)}",
        css_family_configured_sans_family=f"{_css_family(configured_sans_family)}",
        stacks_youtube=f"{stacks['youtube']}",
        stacks_synthetic=f"{stacks['synthetic']}",
    ).encode()

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self) -> None:
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(html)

        def log_message(self, format: str, *args: object) -> None:  # ruff: ignore[builtin-argument-shadowing] -- Match the standard-library override.
            pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        driver.set_window_size(1200, 400)
        driver.get(f"http://127.0.0.1:{server.server_port}/")
        result = driver.execute_script(
            _browser_program("missing-named-stack-metrics.cts")
        )
        driver.save_screenshot(str(output / "missing-named-stack.png"))
    finally:
        server.shutdown()
        server.server_close()
        thread.join()

    widths = {identifier: values["width"] for identifier, values in result.items()}
    ordinary_stacks = ("youtube", "synthetic")
    failures = [
        identifier
        for identifier in ordinary_stacks
        if abs(widths[identifier] - widths["reference"]) > 1.0
        or abs(widths[identifier] - widths["fallback"]) <= 1.0
    ]
    failed = bool(failures)
    (output / "missing-named-stack.json").write_text(
        json.dumps(
            {
                "fallback_family": fallback_family,
                "configured_sans_family": configured_sans_family,
                "stacks": stacks,
                "result": result,
                "failures": failures,
                "failed": failed,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(  # ruff: ignore[print] -- The command reports the pass/fail result.
        f"{'FAIL' if failed else 'PASS'}: missing first families preserve later CSS stacks"
    )
    return failed


def _wait_for_browser(log: Path, port: int) -> None:
    """Observe Marionette's post-listen announcement, then connect once."""
    marker = f"Listening on port {port}".encode()

    def listening() -> bool:
        return any(
            b"Marionette" in line and marker in line
            for line in log.read_bytes().splitlines()
        )

    FileChanges(log.parent).wait(listening, timeout=30)
    # Gecko announces readiness after asyncListen; the driver makes the real
    # protocol connection below, without speculative TCP clients.


def _write_browser_profile(
    profile: Path, prefs: dict[str, object], user_content_css: Path | None
) -> None:
    """Write isolated Gecko preferences and optional content CSS."""
    if user_content_css:
        chrome = profile / "chrome"
        chrome.mkdir()
        (chrome / "userContent.css").write_text(
            user_content_css.read_text(encoding="utf-8"), encoding="utf-8"
        )
    (profile / "user.js").write_text(
        "\n".join(
            f"user_pref({json.dumps(k)}, {json.dumps(v)});" for k, v in prefs.items()
        ),
        encoding="utf-8",
    )


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
        "--suite",
        choices=[
            "digits",
            "multilingual",
            "private-use",
            "apple-stack",
            "apple-platform",
            "missing-named-stack",
            "compatibility",
            "emoji-presentation",
            "webfonts",
        ],
        default="digits",
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
    parser.add_argument("--user-content-css", type=Path)
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
    sans_family, serif_family, monospace_family = _fontconfig_role_families()
    prefs = {
        "marionette.port": port,
        "zen.welcome-screen.seen": True,
        "browser.startup.page": 0,
        "font.name.sans-serif.x-western": sans_family,
        "font.name.serif.x-western": serif_family,
        "font.name.monospace.x-western": monospace_family,
        "layout.css.devPixelsPerPx": "1.0",
        "gfx.font_rendering.fontconfig.max_generic_substitutions": args.generic_substitutions,
        "toolkit.legacyUserProfileCustomizations.stylesheets": True,
    }
    with tempfile.TemporaryDirectory(prefix="gecko-font-check-") as profile:
        _write_browser_profile(Path(profile), prefs, args.user_content_css)
        command = [
            args.browser,
            "-no-remote",
            "-profile",
            profile,
            "-marionette",
        ]
        if not args.headed:
            command.append("-headless")
        with (args.output / "browser.log").open("w", encoding="utf-8") as log:
            # Only this isolated test browser needs privileged graphics inspection.
            browser = subprocess.Popen(  # ruff: ignore[subprocess-without-shell-equals-true] -- No shell; the caller selects a local browser.
                command,
                stdout=log,
                stderr=subprocess.STDOUT,
                env=os.environ | {"MOZ_REMOTE_ALLOW_SYSTEM_ACCESS": "1"},
            )
            driver = None
            try:
                _wait_for_browser(args.output / "browser.log", port)
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
                    "private-use": check_private_use,
                    "apple-stack": check_apple_system_stack,
                    "apple-platform": check_apple_platform_namespace,
                    "missing-named-stack": check_missing_named_stack,
                    "compatibility": check_font_compatibility,
                    "emoji-presentation": check_emoji_presentation,
                    "webfonts": check_webfonts,
                }[args.suite]
                return check(driver, args.output)
            finally:
                try:
                    if driver is not None:
                        driver.quit()
                finally:
                    browser.terminate()
                    try:
                        wait_child(browser, timeout=5)
                    except subprocess.TimeoutExpired:
                        browser.kill()
                        wait_child(browser, timeout=5)


if __name__ == "__main__":
    raise SystemExit(main())
