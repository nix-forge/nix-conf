#!/usr/bin/env python3
# ruff: file-ignore[print]
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
from typescript_sources import javascript_source

SOURCE_ENCODINGS = 7829


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
            (Path(__file__).with_name("fixtures") / "mutant-emoji.html.in")
            .read_text(encoding="utf-8")
            .removesuffix("\n")
            .replace("__font_face__", font_face)
            .replace("__family__", family),
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
                _browser_program("mutant-font-load.cts"),
                family,
            )
            assert isinstance(loaded, int), loaded
            assert args.installed or loaded > 0, "Web font failed to load"
            results = driver.execute_script(
                _browser_program("mutant-emoji-canvas-metrics.cts"),
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
