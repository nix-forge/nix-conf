"""Disposable service-manager double for the recovery scenarios."""

# ruff: file-ignore[print] -- systemctl show is a stdout protocol.

import pathlib
import subprocess
import sys

action, unit = sys.argv[1:3]
if action == "show":
    print("LoadState=loaded\nActiveState=active")
elif action in {"stop", "start"}:
    with (
        pathlib.Path(__file__).with_name("events").open("a", encoding="utf-8") as output
    ):
        output.write(action + " " + unit + "\n")
    if action == "start" and unit == "second.service":
        if (
            pathlib.Path(__file__).with_name("failure-mode").read_text(encoding="utf-8")
            == "nonzero"
        ):
            raise SystemExit(1)
        subprocess.Popen([sys.executable, "-c", "import time; time.sleep(10)"])
else:
    raise SystemExit(9)
