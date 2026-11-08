"""Record reload ordering for the gated desktop launcher."""

import os
import sys
from pathlib import Path

with Path(os.environ["CODEX_TEST_EVENTS"]).open("a", encoding="utf-8") as stream:
    stream.write("reload\n")
if os.environ.get("CODEX_TEST_RELOAD_FAIL"):
    sys.exit(3)
