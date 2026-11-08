"""Provide controlled child behavior for process ownership tests."""

from pathlib import Path

Path("flake.lock").write_text("changed", encoding="utf-8")
