#!/usr/bin/env python3
"""Check the selected emoji font against Unicode's emoji-test.txt.

Requires uharfbuzz. The input file must be Unicode's official display-test data.
Fully qualified sequences and standalone emoji components must each shape into
a non-missing advancing glyph, optionally with overlapping zero-advance layers. This checks coverage and composition, not visual artwork.
"""

import argparse
import shutil
import subprocess  # ruff: ignore[suspicious-subprocess-import] -- Queries the local Fontconfig selection.
from pathlib import Path

import uharfbuzz as hb
from emoji_support import composed, emoji_entries, shape


def main() -> bool:
    """Check an explicit font, or the default selected by Fontconfig.

    Returns:
        Whether any emoji fails to shape into one supported glyph.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--emoji-data", type=Path, required=True)
    parser.add_argument("--font", type=Path, help="Defaults to fc-match emoji")
    parser.add_argument(
        "--face-index", type=int, default=0, help="Collection face index for --font"
    )
    args = parser.parse_args()
    face_index = args.face_index
    font_path = args.font
    if font_path is None:
        fc_match = shutil.which("fc-match")
        if fc_match is None:
            parser.error("fc-match is unavailable; supply --font")
        selection = subprocess.check_output(  # ruff: ignore[subprocess-without-shell-equals-true] -- Fixed arguments to the discovered local Fontconfig executable.
            [fc_match, "-f", "%{file}\t%{index}", "emoji"],
            text=True,
        ).split("\t")
        font_path = Path(selection[0])
        face_index = int(selection[1]) & 0xFFFF
    font = hb.Font(hb.Face(font_path.read_bytes(), face_index))
    entries = emoji_entries(args.emoji_data)
    failures = []
    for sequence, description in entries:
        if not composed(shape(font, sequence)):
            failures.append(description)
    print(f"Selected font: {font_path}")  # ruff: ignore[print] -- Diagnostic CLI output.
    print(  # ruff: ignore[print] -- Diagnostic CLI output.
        f"{'FAIL' if failures else 'PASS'}: {len(entries) - len(failures)}/{len(entries)} RGI entries supported"
    )
    for description in failures:
        print(description)  # ruff: ignore[print] -- Report the exact unsupported sequences.
    return bool(failures)


if __name__ == "__main__":
    raise SystemExit(main())
