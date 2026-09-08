#!/usr/bin/env python3
# ruff: file-ignore[assert, print]
# Assertions and printed pass/fail summaries are intentional in this test CLI.
"""Exercise font selection plus shaping for every Mutant source encoding.

Requires the browser runner's Selenium/Pillow environment plus uharfbuzz.
Use --font for the built TTF and --artwork for the extracted codepoint SVG
directory. Remaining arguments are the shared browser runner's options.
"""

import argparse
import functools
import http.server
import json
import tempfile
import threading
from pathlib import Path

import check_font_rendering as runner
import uharfbuzz as hb

SOURCE_ENCODINGS = 7829


def main() -> int:
    """Run the complete browser font-selection regression.

    Returns:
        Zero when all source sequences render at the expected advance.

    """
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--font", type=Path, required=True)
    parser.add_argument("--artwork", type=Path, required=True)
    parser.add_argument("--installed", action="store_true")
    args, remaining = parser.parse_known_args()
    font_bytes = args.font.read_bytes()
    family = "Mutant Standard Emoji" if args.installed else "MutantTest"
    shaper = hb.Font(hb.Face(font_bytes))
    samples = []
    for path in sorted(args.artwork.glob("*.svg")):
        text = "".join(chr(int(cp, 16)) for cp in path.stem.split("-"))
        buffer = hb.Buffer()
        buffer.add_str(text)
        buffer.guess_segment_properties()
        hb.shape(shaper, buffer)
        assert len(buffer.glyph_infos) == 1, path.name
        samples.append({
            "encoding": path.stem,
            "text": text,
            "width": buffer.glyph_positions[0].x_advance / shaper.face.upem * 48,
        })
    assert len(samples) == SOURCE_ENCODINGS, len(samples)

    with tempfile.TemporaryDirectory(prefix="mutant-browser-") as directory:
        root = Path(directory)
        (root / "font.ttf").write_bytes(font_bytes)
        font_face = (
            ""
            if args.installed
            else "@font-face{font-family:MutantTest;src:url(font.ttf)}"
        )
        (root / "index.html").write_text(
            "<!doctype html><meta charset='utf-8'><style>"
            + font_face
            + """
body{background:#202124;color:#eee;font:18px sans-serif;padding:24px}
.emoji{font:48px '"""
            + family
            + """';color:pink}
</style><p>Mutant Standard Emoji</p>
<p class="emoji">😀😁😂😃😄😅😆😇😈😉😊😋😌😍</p>
<p>Custom characters and joined sequences</p><p class="emoji" id="custom"></p>
<p>Artwork by Caius Nocturne · CC BY-NC-SA 4.0 · mutant.tech</p>""",
            encoding="utf-8",
        )
        handler = functools.partial(
            http.server.SimpleHTTPRequestHandler, directory=root
        )
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()

        def check(driver: runner.webdriver.Firefox, output: Path) -> bool:
            driver.get(f"http://127.0.0.1:{server.server_port}/index.html")
            loaded = driver.execute_async_script(
                "const family=arguments[0], done=arguments[1]; document.fonts.load('48px '+JSON.stringify(family),'😀')"
                ".then(fonts=>done(fonts.length)).catch(error=>done(String(error)));",
                family,
            )
            assert isinstance(loaded, int), loaded
            assert args.installed or loaded > 0, "Web font failed to load"
            results = driver.execute_script(
                """const samples=arguments[0];
const ctx=document.createElement('canvas').getContext('2d');
ctx.font='48px '+JSON.stringify(arguments[1]);
const failures=samples.flatMap(s=>{
    const actual=ctx.measureText(s.text).width;
    return Math.abs(actual-s.width)>0.1 ? [{...s,actual}] : [];
});
document.querySelector('#custom').textContent = [
    '1f44d-fe0f-101650-101613', '1f3f3-fe0f-200d-26a7',
    '1f3f3-200d-1f308', '101698', '101691'
].map(name=>samples.find(s=>s.encoding===name).text).join(' ');
return {total:samples.length, failures};""",
                samples,
                family,
            )
            driver.find_element("css selector", "body").screenshot(
                str(output / "mutant.png")
            )
            (output / "results.json").write_text(json.dumps(results, indent=2))
            failed = len(results["failures"])
            print(
                f"{'FAIL' if failed else 'PASS'}: {results['total'] - failed}/{results['total']} browser sequences match the font advance"
            )
            return bool(failed)

        try:
            return runner.main(digit_check=check, argv=remaining)
        finally:
            server.shutdown()
            server.server_close()


if __name__ == "__main__":
    raise SystemExit(main())
