"""An application that observes its own policy at the point of exec."""

import json
import os
import sys
from pathlib import Path

policy = (
    Path(os.environ["XDG_RUNTIME_DIR"])
    / "systemd/user"
    / f"app-org.chromium.Chromium-{os.getpid()}.scope.d/90-codex-slice.conf"
)
with Path(os.environ["CODEX_TEST_EVENTS"]).open("a", encoding="utf-8") as stream:
    stream.write(
        json.dumps({
            "pid": os.getpid(),
            "policy": policy.read_text(),
            "args": sys.argv[1:],
        })
        + "\n"
    )
sys.exit(7)
