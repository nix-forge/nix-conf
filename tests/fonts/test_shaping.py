"""Valid layered emoji pass; missing, adjacent, and displaced glyphs fail."""

from types import SimpleNamespace

import pytest
from emoji_support import composed


@pytest.mark.parametrize(
    ("advances", "offsets", "ids", "expected"),
    [
        pytest.param([2048], [0], [7], True, id="single-glyph"),
        pytest.param([2048, 0], [0, -2048], [7, 8], True, id="overlapping-layers"),
        pytest.param([2048, 2048], [0, 0], [7, 8], False, id="unjoined-glyphs"),
        pytest.param([2048, 0], [0, -4096], [7, 8], False, id="displaced-layer"),
        pytest.param([2048], [0], [0], False, id="missing-glyph"),
        pytest.param([], [], [], False, id="empty"),
        pytest.param([0], [0], [7], False, id="no-advance"),
        pytest.param([-1], [0], [7], False, id="negative-advance"),
    ],
)
def test_composition_contract(
    advances: list[int], offsets: list[int], ids: list[int], expected: bool
) -> None:
    """Check image composition independently of any installed font artwork."""
    buffer = SimpleNamespace(
        glyph_infos=[SimpleNamespace(codepoint=i) for i in ids],
        glyph_positions=[
            SimpleNamespace(x_advance=a, x_offset=o)
            for a, o in zip(advances, offsets, strict=True)
        ],
    )
    assert composed(buffer) is expected
