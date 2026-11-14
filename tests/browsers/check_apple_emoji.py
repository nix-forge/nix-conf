#!/usr/bin/env python3
"""Check installed Apple emoji selection, composition and color in a real browser.

Requires Selenium, Pillow and uharfbuzz. Pass the pinned Unicode emoji-test.txt
with --emoji-data and the installed font with --font, followed by the shared
browser runner's options. Does not enable downloaded color-bitmap fonts.
"""

import argparse
import json
import sys
from pathlib import Path

import check_font_rendering as runner
import uharfbuzz as hb
from typescript_sources import javascript_source

RGI_ENTRIES = 3953
MIN_COLORED_ENTRIES = 3500

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "fonts"))
from emoji_support import (  # ruff: ignore[module-import-not-at-top-of-file]
    emoji_entries,
    shape,
)


def _browser_program(name: str) -> str:
    """Load the checked browser function.

    Returns:
        The browser script with WebDriver's receiver and arguments preserved.

    """
    source = javascript_source(Path(__file__).with_name("fixtures") / name)
    return (
        "const module = {exports: null};\n"
        + source
        + "\nreturn module.exports.apply(this, arguments);"
    )


def main() -> bool:
    """Run the installed-font regression.

    Returns:
        Whether any check fails.

    """
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--font", type=Path, required=True)
    parser.add_argument("--emoji-data", type=Path, required=True)
    args, remaining = parser.parse_known_args()
    font = hb.Font(hb.Face(args.font.read_bytes()))
    samples = []
    for text, _description in emoji_entries(args.emoji_data):
        buffer = shape(font, text)
        samples.append({
            "text": text,
            "code": " ".join(f"{ord(c):04X}" for c in text),
            "width": sum(p.x_advance for p in buffer.glyph_positions)
            / font.face.upem
            * 48,
        })

    def check(driver: runner.webdriver.Firefox, output: Path) -> bool:
        driver.set_context("chrome")
        bitmaps = driver.execute_script(
            'return Services.prefs.getBoolPref("gfx.downloadable_fonts.keep_color_bitmaps", false)'
        )
        driver.set_context("content")
        driver.get("about:blank")
        driver.set_window_size(1200, 700)
        loaded = driver.execute_async_script(
            _browser_program("apple-emoji-font-load.cts")
        )
        result = driver.execute_script(
            _browser_program("apple-emoji-canvas-metrics.cts"),
            samples,
        )
        result["localFontLoaded"] = loaded is True
        result["downloadedColorBitmaps"] = bitmaps
        driver.find_element("css selector", "body").screenshot(
            str(output / "apple-emoji.png")
        )
        (output / "results.json").write_text(json.dumps(result, indent=2) + "\n")
        print(json.dumps(result, indent=2))  # ruff: ignore[print] -- Diagnostic CLI output.
        return bool(
            bitmaps
            or result["failures"]
            or result["total"] != RGI_ENTRIES
            or result["colored"] < MIN_COLORED_ENTRIES
            or not result["localFontLoaded"]
        )

    return runner.main(digit_check=check, argv=remaining)


if __name__ == "__main__":
    raise SystemExit(main())
