"""Check Launch Services record extraction with literal application paths."""

import shutil
import subprocess  # ruff: ignore[suspicious-subprocess-import] -- Declared GNU awk and fixed source.
from pathlib import Path

import pytest

SOURCE = (
    Path(__file__).resolve().parents[2]
    / "modules/home/browsers/shared/registered-browser.awk"
)


@pytest.mark.parametrize("last_record", [False, True])
def test_extracts_one_literal_path_record(last_record: bool) -> None:
    """Regex metacharacters in a path must not select a different application."""
    awk = shutil.which("gawk")
    assert awk is not None
    wanted = "----------\npath: /Applications/Browser [Beta].app (0x1)\nversion: 2\n"
    other = "----------\npath: /Applications/Browser B.app (0x2)\nversion: 1\n"
    records = other + wanted if last_record else wanted + other
    result = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] -- Fixed interpreter, source, and literal test input.
        [awk, "-v", "app_path=/Applications/Browser [Beta].app", "-f", str(SOURCE)],
        input=records,
        text=True,
        capture_output=True,
        check=True,
    )
    assert result.stdout == wanted
