#!/usr/bin/env python3
"""Build original geometric fonts for CSS matching tests without vendor data.

Family names exercise external compatibility identifiers. These fonts contain
only rectangles and triangles drawn here, never Apple glyphs or font tables.
They are test fixtures covered by the repository's MIT license.
"""

import sys
from pathlib import Path

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen


def build_font(
    output: Path, family: str, identifier: str, *, private_use: bool
) -> None:
    """Write a deterministic geometric font with ASCII and optional PUA shapes."""
    codepoints = list(range(32, 127))
    if private_use:
        codepoints.extend((0xF802, 0xF803, 0xF804, 0xF8FF))
    cmap = {codepoint: f"uni{codepoint:04X}" for codepoint in codepoints}
    order = [".notdef", *cmap.values()]
    glyphs = {}
    metrics = {}
    for index, name in enumerate(order):
        pen = TTGlyphPen(None)
        width = 900 + index % 3 * 100
        if name != "uni0020":
            pen.moveTo((100, 0))
            pen.lineTo((width - 100, 0))
            pen.lineTo((width - 100, 700))
            if index % 2:
                pen.lineTo((100, 400))
            else:
                pen.lineTo((100, 700))
            pen.closePath()
        glyphs[name] = pen.glyph()
        metrics[name] = (width, 100)
    builder = FontBuilder(1000, isTTF=True)
    builder.setupGlyphOrder(order)
    builder.setupCharacterMap(cmap)
    builder.setupGlyf(glyphs)
    builder.setupHorizontalMetrics(metrics)
    builder.setupHorizontalHeader(ascent=800, descent=-200)
    builder.setupNameTable({
        "familyName": family,
        "styleName": "Regular",
        "uniqueFontIdentifier": identifier,
        "fullName": f"{family} Synthetic Test Fixture",
        "psName": identifier,
        "version": "Version 1.0",
        "copyright": "Original geometric test fixture; repository MIT license.",
    })
    builder.setupOS2(
        sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200
    )
    builder.setupPost()
    builder.setupMaxp()
    builder.font.recalcTimestamp = False
    builder.setupHead(unitsPerEm=1000, created=2082844800, modified=2082844800)
    builder.save(output)


def main() -> None:
    """Create the two protocol-family fixtures in the requested directory."""
    output = Path(sys.argv[1])
    output.mkdir(parents=True, exist_ok=True)
    build_font(
        output / "private-use.ttf",
        "Lucida Grande",
        "SyntheticPrivateUse",
        private_use=True,
    )
    build_font(
        output / "platform.ttf", "SF Pro", "SyntheticPlatform", private_use=False
    )


if __name__ == "__main__":
    main()
