"""Validate generated artifacts in an isolated build or VM fixture."""

import pathlib
import sys
import tomllib

with pathlib.Path(sys.argv[1]).open("rb") as source:
    prompt = tomllib.load(source)
assert prompt["character"]["success_symbol"] == "[>](bold green)"
assert prompt["directory"]["style"] == "bold blue"
