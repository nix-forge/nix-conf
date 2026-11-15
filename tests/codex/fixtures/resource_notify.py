"""Record an actual notification command without accessing desktop D-Bus."""

import json
import os
import sys
from pathlib import Path

with Path(os.environ["CODEX_TEST_NOTIFICATIONS"]).open("a", encoding="utf-8") as stream:
    stream.write(json.dumps(sys.argv[1:]) + "\n")
