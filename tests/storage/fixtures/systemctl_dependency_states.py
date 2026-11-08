"""Disposable service-manager double for the recovery scenarios."""

# ruff: file-ignore[print] -- systemctl show is a stdout protocol.

import json
import pathlib
import sys

path = pathlib.Path(__file__).with_name("unit-states.json")
state = json.loads(path.read_text(encoding="utf-8"))
action, unit = sys.argv[1:3]
if action == "show":
    print("LoadState=loaded\nActiveState=" + state[unit])
elif action == "stop":
    state[unit] = "inactive"
    if unit == "parent.service":
        state["child.service"] = "inactive"
    path.write_text(json.dumps(state), encoding="utf-8")
elif action == "start":
    state[unit] = "active"
    path.write_text(json.dumps(state), encoding="utf-8")
else:
    raise SystemExit(9)
