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

RGI_ENTRIES = 3953
MIN_COLORED_ENTRIES = 3500

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "fonts"))
from emoji_support import (  # ruff: ignore[module-import-not-at-top-of-file]
    emoji_entries,
    shape,
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
        loaded = driver.execute_async_script("""
const done = arguments[0];
const font = new FontFace('AppleTest', 'local("AppleColorEmoji")');
font.load().then(f => {document.fonts.add(f); done(true)}).catch(e => done(String(e)));
""")
        result = driver.execute_script(
            """
const samples = arguments[0], canvas = document.createElement('canvas');
canvas.width = 96; canvas.height = 96;
const ctx = canvas.getContext('2d', {willReadFrequently:true});
ctx.font = '48px AppleTest'; ctx.fillStyle = '#ddd';
const failures = []; let colored = 0;
for (const sample of samples) {
    ctx.clearRect(0,0,96,96);
    const width = ctx.measureText(sample.text).width;
    ctx.fillText(sample.text,8,64);
    const pixels = ctx.getImageData(0,0,96,96).data;
    let visible = 0, color = 0;
    for(let i=0;i<pixels.length;i+=4) {
    if(pixels[i+3]>32) {
        visible++;
        if(Math.max(pixels[i],pixels[i+1],pixels[i+2])-
            Math.min(pixels[i],pixels[i+1],pixels[i+2])>35) color++;
    }
    }
    if(color>10) colored++;
    if(Math.abs(width-sample.width)>0.1 || visible<10)
    failures.push({code:sample.code,width,expected:sample.width,visible});
}
document.body.style = 'background:#202124;color:#eee;padding:28px;font:18px sans-serif';
document.body.innerHTML = '<h1>Apple Color Emoji · installed Linux font</h1>'+
    '<p>Versioned release: macos-26-20260722-484daf4e · downloaded bitmap fonts disabled</p>'+
    '<div style="font:48px AppleTest;line-height:1.6">'+
    '😀 😎 🥰 😭 🫩 🫪 🫯 🐱 🦊 🦋 🌻 🍎 🍕 🎉 ❤️<br>'+
    '👍🏻 👍🏽 👍🏿 👩🏽‍💻 👨🏻‍🚀 🧑🏿‍🚒 🫱🏻‍🫲🏼 🫱🏿‍🫲🏻<br>'+
    '👩🏻‍❤️‍💋‍👩🏿 🧑🏽‍🤝‍🧑🏻 👨‍👩‍👧‍👦 🏳️‍🌈 🇺🇸 🇯🇵 ♀️ ♂️ ⚕️ 🏴󠁧󠁢󠁳󠁣󠁴󠁿 1️⃣</div>'+
    '<p>Font artwork © Apple Inc. Linux conversion: samuelngs/apple-emoji-ttf.</p>';
return {total:samples.length,failures,colored,localFontLoaded:document.fonts.check('48px AppleTest')};
""",
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
