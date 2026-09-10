"""Make Noctalia's supplied UI color pairs readable without changing surfaces."""

from __future__ import annotations

import json
import sys
from pathlib import Path

TEXT_CONTRAST = 4.75
SRGB_LINEAR_THRESHOLD = 0.04045
RGB = tuple[int, ...]


def rgb(value: str) -> RGB:
    """Read an opaque palette color.

    Returns:
        The three sRGB byte values.

    """
    return tuple(int(value[index : index + 2], 16) for index in (1, 3, 5))


def luminance(color: RGB) -> float:
    """Calculate WCAG relative luminance for sRGB channels.

    Returns:
        Relative luminance from zero to one.

    """
    channels = [value / 255 for value in color]
    linear = [
        value / 12.92
        if value <= SRGB_LINEAR_THRESHOLD
        else ((value + 0.055) / 1.055) ** 2.4
        for value in channels
    ]
    return sum(
        value * weight
        for value, weight in zip(linear, (0.2126, 0.7152, 0.0722), strict=True)
    )


def contrast(first: RGB, second: RGB) -> float:
    """Calculate the contrast between two opaque colors.

    Returns:
        The WCAG contrast ratio, from one to twenty-one.

    """
    low, high = sorted((luminance(first), luminance(second)))
    return (high + 0.05) / (low + 0.05)


def readable(foreground: str, backgrounds: list[str], endpoint: str) -> str:
    """Keep passing colors; otherwise blend minimally toward the theme's text.

    Returns:
        The first opaque hex color that passes on every background.

    Raises:
        ValueError: No blend toward the endpoint meets the contrast target.

    """
    start, end = rgb(foreground), rgb(endpoint)
    surfaces = [rgb(value) for value in backgrounds]
    for step in range(256):
        candidate = tuple(
            round(a + (b - a) * step / 255) for a, b in zip(start, end, strict=True)
        )
        if all(contrast(candidate, surface) >= TEXT_CONTRAST for surface in surfaces):
            return "#" + "".join(f"{value:02x}" for value in candidate)
    message = "The palette cannot meet the UI text contrast target with its foreground endpoints"
    raise ValueError(message)


def prepare(mode: dict) -> None:
    """Correct UI roles while preserving the source terminal palette and surfaces."""
    surfaces = [mode["mSurface"], mode["mSurfaceVariant"]]
    # All supported schemes are dark. White is the fallback only when the
    # scheme's primary text itself cannot meet the target on both surfaces.
    mode["mOnSurface"] = readable(mode["mOnSurface"], surfaces, "#ffffff")
    mode["mOnSurfaceVariant"] = readable(
        mode["mOnSurfaceVariant"], surfaces, mode["mOnSurface"]
    )
    for role in ("Primary", "Secondary", "Tertiary", "Error"):
        fill, text = "m" + role, "mOn" + role
        mode[fill] = readable(mode[fill], surfaces, mode["mOnSurface"])
        mode[text] = readable(mode[text], [mode[fill]], "#000000")
    # The pinned shell maps hover to tertiary when expanding fixed palettes.
    # Keep the legacy JSON fields consistent with what actually renders.
    mode["mHover"] = mode["mTertiary"]
    mode["mOnHover"] = mode["mOnTertiary"]


def main() -> None:
    """Transform a generated fixed palette into the installed JSON artifact."""
    source, destination = map(Path, sys.argv[1:])
    palette = json.loads(source.read_text())
    prepare(palette["dark"])
    destination.write_text(json.dumps(palette, indent=2) + "\n")


if __name__ == "__main__":
    main()
