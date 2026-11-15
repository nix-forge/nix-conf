"""Provide controlled child behavior for process ownership tests."""

import sys
from pathlib import Path

Path(sys.argv[1]).unlink()
