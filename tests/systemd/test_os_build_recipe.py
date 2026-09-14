"""Regression coverage for desktop build output handling."""

from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]


def test_os_build_skips_the_expensive_output_monitor() -> None:
    """Keep the large desktop closure out of nom's JSON graph renderer."""
    justfile = (REPOSITORY_ROOT / "justfile").read_text()
    recipe = justfile.split("os-build hostname *args:", maxsplit=1)[1].split(
        "\n\n", maxsplit=1
    )[0]

    assert "nh os build" in recipe
    assert "--no-nom" in recipe
