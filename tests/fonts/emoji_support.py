"""Unicode fixtures and shaping contracts shared by font integration tests."""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from pathlib import Path

import uharfbuzz as hb


def emoji_entries(data: Path) -> list[tuple[str, str]]:
    """Read the Unicode fixture.

    Returns:
        Fully qualified emoji and standalone components with their descriptions.

    Raises:
        ValueError: If the fixture contains no qualifying sequences.

    """
    entries = []
    for line in data.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        code, rest = line.split(";", 1)
        status, description = rest.split("#", 1)
        if status.strip() in {"fully-qualified", "component"}:
            entries.append((
                "".join(chr(int(c, 16)) for c in code.split()),
                description.strip(),
            ))
    if not entries:
        message = "No RGI entries found in the supplied emoji-test.txt"
        raise ValueError(message)
    return entries


def shape(font: hb.Font, sequence: str) -> hb.Buffer:
    """Check the font contract.

    Returns:
        A shaped emoji buffer without invisible default-ignorable glyphs.

    """
    buffer = hb.Buffer()
    buffer.add_str(sequence)
    buffer.guess_segment_properties()
    buffer.flags = hb.BufferFlags.REMOVE_DEFAULT_IGNORABLES
    hb.shape(font, buffer)
    return buffer


def composed(buffer: hb.Buffer) -> bool:
    """Check the font contract.

    Returns:
        Whether glyphs form one advancing image without missing glyphs.

    """
    if not buffer.glyph_infos or any(g.codepoint == 0 for g in buffer.glyph_infos):
        return False
    positions = buffer.glyph_positions
    advance = positions[0].x_advance
    return advance > 0 and all(
        p.x_advance == 0 and -advance <= p.x_offset <= 0 for p in positions[1:]
    )
