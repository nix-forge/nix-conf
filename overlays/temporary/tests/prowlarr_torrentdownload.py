"""Exercise the filters from the installed Cardigann definition."""

import re
import sys
from pathlib import Path
from typing import TypedDict

import yaml

with Path(sys.argv[1]).open(encoding="utf-8") as source:
    definition = yaml.safe_load(source)


class Filter(TypedDict):
    """One fixed Cardigann replacement expression."""

    name: str
    args: tuple[str, str]


def apply_filters(value: str, filters: list[Filter]) -> str:
    """Apply the supported Cardigann replacement filters.

    Returns:
        The rewritten fixture string.

    """
    for item in filters:
        assert item["name"] == "re_replace"
        pattern, replacement = item["args"]
        # These patterns use the common Python/.NET regex subset. Translate
        # Cardigann's .NET numbered replacement groups for this offline check.
        replacement = re.sub(r"\$(\d+)", r"\\g<\1>", replacement)
        value = re.sub(pattern, replacement, value)
    return value


search = definition["search"]
keywords = search.get("keywordsfilters", [])
assert apply_filters("Artist That's It", keywords) == "Artist Thats It"
assert apply_filters("Artist That’s It", keywords) == "Artist Thats It"
assert apply_filters("Artist Normal Album", keywords) == "Artist Normal Album"
titles = search["fields"]["title"].get("filters", [])
for quality in ["FLAC", "Mp3 320kbps", "MP3 320kbps"]:
    suffix = f"Album (2023) {quality} [GROUP]"
    assert apply_filters(f"Artist   {suffix}", titles) == f"Artist - {suffix}"
    assert apply_filters(f"Artist - {suffix}", titles) == f"Artist - {suffix}"
for title in ["Artist - Album", "Film   (2023) 1080p", "Artist   Live Session"]:
    assert apply_filters(title, titles) == title
print("Cardigann music search and title regressions passed")
