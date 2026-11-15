"""Disposable service-manager double for the recovery scenarios."""

# ruff: file-ignore[print] -- systemctl show is a stdout protocol.

import pathlib
import sys

p = pathlib.Path(__file__).with_name("events")
action, unit = sys.argv[1:3]
if action == "show":
    print(
        "LoadState=loaded\nActiveState="
        + ("active" if unit == "writer.service" else "inactive")
    )
elif action in {"stop", "start"}:
    with p.open("a", encoding="utf-8") as output:
        output.write(action + " " + unit + "\n")
else:
    raise SystemExit(9)
