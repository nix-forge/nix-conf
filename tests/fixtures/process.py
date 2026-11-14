"""Provide controlled child lifecycles for process ownership tests."""

# ruff: file-ignore[suspicious-subprocess-import, subprocess-without-shell-equals-true, print] -- Tests deliberately create descendants and observable output.
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

mode, *args = sys.argv[1:]
if mode == "sleep":
    time.sleep(float(args[0]))
elif mode == "pause":
    signal.pause()
elif mode == "marker-stall":
    Path(args[0]).touch()
    time.sleep(float(args[1]))
elif mode == "delayed-marker":
    time.sleep(float(args[1]))
    Path(args[0]).touch()
    time.sleep(float(args[2]))
elif mode == "spawn-delayed":
    stream = None if args[3] == "inherit" else subprocess.DEVNULL
    subprocess.Popen(
        [sys.executable, __file__, "delayed-marker", *args[:3]],
        stdout=stream,
        stderr=stream,
    )
elif mode == "self-pid-pause":
    Path(args[0]).write_text(str(os.getpid()), encoding="utf-8")
    signal.pause()
elif mode == "spawn-pause":
    child = subprocess.Popen([sys.executable, __file__, "pause"])
    Path(args[0]).write_text(str(child.pid), encoding="utf-8")
    if args[1] == "wait":
        signal.pause()
elif mode == "stdin-log":
    with Path(args[0]).open("a", encoding="utf-8") as output:
        output.write(sys.stdin.read())
elif mode == "stdin-barrier":
    print("ready", flush=True)
    sys.stdin.buffer.read(1)
else:
    message = "Unknown process fixture mode"
    raise SystemExit(message)
