"""Check installed Noctalia palette artifacts against UI contrast requirements."""

from __future__ import annotations

import json
import sys
from pathlib import Path

MINIMUM_TEXT_RATIO = 4.5
MINIMUM_CONTROL_RATIO = 3.0
GENERATION_TARGET = 4.75
SRGB_THRESHOLD = 0.04045


def ratio(first: str, second: str) -> float:
    """Measure two opaque sRGB colors independently of the palette generator.

    Returns:
        The WCAG contrast ratio.

    """
    luminances = []
    for color in (first, second):
        channels = [int(color[index : index + 2], 16) / 255 for index in (1, 3, 5)]
        linear = [
            channel / 12.92
            if channel <= SRGB_THRESHOLD
            else pow((channel + 0.055) / 1.055, 2.4)
            for channel in channels
        ]
        luminances.append(0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2])
    return (max(luminances) + 0.05) / (min(luminances) + 0.05)


def require(condition: bool, message: str) -> None:
    """Stop the check when a generated artifact violates a requirement.

    Raises:
        SystemExit: The named palette requirement failed.

    """
    if not condition:
        raise SystemExit(message)


def main() -> None:
    """Validate every repository-supported scheme through the production renderer."""
    fixtures = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    for name, fixture in fixtures.items():
        original = fixture["original"]["dark"]
        prepared = json.loads(Path(fixture["prepared"]).read_text(encoding="utf-8"))[
            "dark"
        ]
        for role in ("mSurface", "mSurfaceVariant", "mShadow", "mOutline", "terminal"):
            require(
                prepared[role] == original[role], f"{name}: changed preserved {role}"
            )
        surfaces = ("mSurface", "mSurfaceVariant")
        foregrounds = (
            "mOnSurface",
            "mOnSurfaceVariant",
            "mPrimary",
            "mSecondary",
            "mTertiary",
            "mError",
        )
        measured = []
        for foreground in foregrounds:
            for background in surfaces:
                measured.append(ratio(prepared[foreground], prepared[background]))
                require(
                    measured[-1] >= MINIMUM_TEXT_RATIO,
                    f"{name}: {foreground} on {background} fails text contrast",
                )
            if all(
                ratio(original[foreground], original[s]) >= GENERATION_TARGET
                for s in surfaces
            ):
                require(
                    prepared[foreground] == original[foreground],
                    f"{name}: changed an already readable {foreground}",
                )
        for role in ("Primary", "Secondary", "Tertiary", "Error", "Hover"):
            measured.append(ratio(prepared["mOn" + role], prepared["m" + role]))
            require(
                measured[-1] >= MINIMUM_TEXT_RATIO, f"{name}: unreadable text on {role}"
            )
        require(
            prepared["mHover"] == prepared["mTertiary"],
            f"{name}: inaccurate hover alias",
        )
        require(
            prepared["mOnHover"] == prepared["mOnTertiary"],
            f"{name}: inaccurate hover text",
        )
        # The personal shell keeps scrollbar thumbs slightly translucent.
        for surface in surfaces:
            channels = [
                round(
                    int(prepared["mOnSurfaceVariant"][i : i + 2], 16) * 0.85
                    + int(prepared[surface][i : i + 2], 16) * 0.15
                )
                for i in (1, 3, 5)
            ]
            thumb = "#" + "".join(f"{channel:02x}" for channel in channels)
            require(
                ratio(thumb, prepared[surface]) >= MINIMUM_CONTROL_RATIO,
                f"{name}: indistinct scrollbar on {surface}",
            )
        sys.stdout.write(
            f"{name}: {len(measured)} text pairs pass; minimum {min(measured):.2f}:1\n"
        )


if __name__ == "__main__":
    main()
