"""Validate generated artifacts in an isolated build or VM fixture."""

import os
import pathlib
import sys
import tomllib

with pathlib.Path(sys.argv[1]).open("rb") as source:
    config = tomllib.load(source)
assert config["icon_theme"] == os.environ["expectedTheme"]
network = next(item for item in config["end"] if item.get("name") == "network")
assert network["bar"][0]["on_click"] == os.environ["expectedCommand"]
assert config["center"][0]["type"] == "clock"
assert len(config["end"]) == 7
