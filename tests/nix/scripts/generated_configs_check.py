"""Validate generated artifacts in an isolated build or VM fixture."""

import os
import pathlib
import sys
import tomllib

with pathlib.Path(sys.argv[1]).open("rb") as handle:
    config = tomllib.load(handle)
assert config == {
    "server": {
        "style": os.environ["expectedStyle"],
        "min_brightness": 5,
        "show_percentage": True,
        "max_volume": 100,
        "keyboard_backlight": False,
        "top_margin": 0.85,
    }
}, config
