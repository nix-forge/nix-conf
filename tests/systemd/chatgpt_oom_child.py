"""Confined OOM allocation with the child selected as the preferred victim."""

from pathlib import Path

Path("/proc/self/oom_score_adj").write_text("1000", encoding="utf-8")
allocation = bytearray(128 * 1024 * 1024)
assert len(allocation) == 128 * 1024 * 1024
