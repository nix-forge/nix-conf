# ruff: file-ignore[pytest-unittest-assertion]
# The sandbox uses the standard-library unittest runner.
"""Regression: valid layered emoji pass; adjacent unjoined glyphs fail."""

import unittest
from types import SimpleNamespace

from emoji_support import composed


class CompositionTests(unittest.TestCase):
    """Exercise the composition contract with controlled glyph positions."""

    def test_composition_contract(self) -> None:
        """Reject missing, unjoined and displaced glyphs; accept overlapping layers."""
        for advances, offsets, ids, expected in [
            ([2048], [0], [7], True),
            ([2048, 0], [0, -2048], [7, 8], True),
            ([2048, 2048], [0, 0], [7, 8], False),
            ([2048, 0], [0, -4096], [7, 8], False),
            ([2048], [0], [0], False),
            ([], [], [], False),
        ]:
            with self.subTest(advances=advances, offsets=offsets, ids=ids):
                buffer = SimpleNamespace(
                    glyph_infos=[SimpleNamespace(codepoint=i) for i in ids],
                    glyph_positions=[
                        SimpleNamespace(x_advance=a, x_offset=o)
                        for a, o in zip(advances, offsets, strict=True)
                    ],
                )
                self.assertEqual(composed(buffer), expected)


if __name__ == "__main__":
    unittest.main()
