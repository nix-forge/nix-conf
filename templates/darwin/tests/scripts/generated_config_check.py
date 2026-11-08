"""Validate generated artifacts in an isolated build or VM fixture."""

import pathlib
import plistlib
import subprocess
import sys

with pathlib.Path(sys.argv[1]).open("rb") as source:
    job = plistlib.load(source)
assert job["Label"] == "org.nix-community.public-example-health"
assert job["RunAtLoad"] is True
assert len(job["ProgramArguments"]) == 1
subprocess.run(job["ProgramArguments"], check=True)
