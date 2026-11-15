"""Provide controlled child behavior for process ownership tests."""

import subprocess
import sys
from pathlib import Path

p = subprocess.Popen([
    sys.executable,
    str(Path(__file__).resolve().parents[2] / "fixtures/process.py"),
    "sleep",
    "30",
])
print(p.pid, flush=True)  # ruff: ignore[print] -- Test child output protocol.
