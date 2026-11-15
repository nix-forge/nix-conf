"""Publish readiness and optionally leave a child for service cleanup."""

# ruff: file-ignore[suspicious-subprocess-import, subprocess-without-shell-equals-true, print] -- A disposable service fixture deliberately creates a child and publishes readiness on stdout.
import json
import os
import signal
import subprocess
import sys

if len(sys.argv) > 1 and sys.argv[1] == "child":
    signal.pause()
else:
    child = subprocess.Popen([sys.executable, __file__, "child"])
    print(json.dumps({"main": os.getpid(), "child": child.pid}), flush=True)
    if len(sys.argv) > 1 and sys.argv[1] == "hold":
        signal.pause()
