#!/usr/bin/env python3
"""Forward package updates to the package repository's maintained entry point."""

import runpy
from pathlib import Path

if __name__ == "__main__":
    updater = Path(__file__).resolve().parents[1] / "pkgs/scripts/update-packages.py"
    runpy.run_path(str(updater), run_name="__main__")
