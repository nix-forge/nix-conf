"""Mark actual execution and alter one source to exercise post-command detection."""

import sys
from pathlib import Path

Path(sys.argv[1]).write_text("ran\n", encoding="utf-8")
Path(sys.argv[2]).write_text("changed by command\n", encoding="utf-8")
