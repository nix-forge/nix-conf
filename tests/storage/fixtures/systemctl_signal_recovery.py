"""Disposable service-manager double for the recovery scenarios."""

# ruff: file-ignore[print] -- systemctl show is a stdout protocol.

import pathlib
import sys

if sys.argv[1] == "show":
    print("LoadState=loaded\nActiveState=active")
elif sys.argv[1] in {"stop", "start"}:
    with (
        pathlib.Path(__file__).with_name("events").open("a", encoding="utf-8") as output
    ):
        output.write(sys.argv[1] + "\n")
else:
    raise SystemExit(9)
