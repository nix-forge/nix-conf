"""Record command arguments while preserving the bootstrap's JSON/file behavior."""

import json
import os
import sys
from pathlib import Path

name = Path(sys.argv[0]).name
arguments = sys.argv[1:]
with Path(os.environ["ARGV_LOG"]).open("a", encoding="utf-8") as output:
    output.write(json.dumps([name, *arguments]) + "\n")

if name == "navidrome":
    if arguments[:1] == ["--configfile"]:
        arguments = arguments[2:]
    if "user" in arguments and "list" in arguments:
        sys.stdout.write(os.environ["FIXTURE_USERS"] + "\n")
    elif arguments[:3] == ["plugin", "edit", "audiomuseai"]:
        source = (
            Path(arguments[arguments.index("--config-file") + 1])
            if "--config-file" in arguments
            else None
        )
        if source is not None:
            Path(os.environ["PLUGIN_CONFIG"]).write_bytes(source.read_bytes())
elif name == "resolve-users":
    sys.stdin.read()
    sys.stdout.write("listener-id,feishin-id\n")
elif name == "expect":
    message = "Fixture accounts should already exist"
    raise SystemExit(message)
elif name in {"jq", "printf", "chmod", "mv", "rm"}:
    executable = json.loads(os.environ["REAL_COMMANDS"])[name]
    os.execv(executable, [executable, *arguments])  # ruff: ignore[start-process-with-no-shell] - transparent fixture adapter for fixed local tools
