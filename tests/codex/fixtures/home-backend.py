"""Report only the configured home and argv, without loading credentials."""

import json
import os
import sys

sys.stdout.write(
    json.dumps({
        "home": os.environ.get("CODEX_HOME"),
        "desktopApp": os.environ.get("CODEX_DESKTOP_APP_PATH"),
        "argv": sys.argv[1:],
    })
    + "\n"
)
raise SystemExit(23 if "--fixture-fail" in sys.argv[1:] else 0)
