"""Record manager calls and compositor policy changes for isolated launcher tests."""

import json
import os
import sys
from pathlib import Path


def notify(event: str) -> None:
    """Publish a lifecycle event to the subscribed test FIFO."""
    if path := os.environ.get("LOCK_FIXTURE_EVENTS"):
        Path(path).write_text(
            json.dumps({
                "event": event,
                "token": os.environ["LOCK_FIXTURE_TOKEN"],
                "pid": os.getpid(),
            })
            + "\n",
            encoding="utf-8",
        )


state = Path(os.environ["LOCK_FIXTURE_STATE"])
call = sys.argv[1:]
with (state / "calls.jsonl").open("a", encoding="utf-8") as output:
    output.write(json.dumps(call) + "\n")
if call[0] == "hyprctl":
    if "instances" in call:
        notify("instances")
        sys.stdout.write((state / "instances.json").read_text(encoding="utf-8"))
    elif "getoption" in call:
        sys.stdout.write((state / "policy.json").read_text(encoding="utf-8"))
    elif "eval" in call:
        value = "allow_session_lock_restore=true" in call[-1]
        ignored = state / "ignored-value.json"
        if not ignored.exists() or json.loads(ignored.read_text()) is not value:
            (state / "policy.json").write_text(
                json.dumps({"bool": value}), encoding="utf-8"
            )
    else:
        message = "Unexpected fixture compositor command"
        raise SystemExit(message)
elif call[0] == "systemctl":
    failed = state / "unit-failed"
    if "is-failed" in call:
        raise SystemExit(0 if failed.exists() else 1)
    if "reset-failed" in call:
        failed.unlink(missing_ok=True)
        raise SystemExit(0)
    assert "start" in call
    if failed.exists():
        raise SystemExit(1)
    notify("manager")
    if release := os.environ.get("LOCK_FIXTURE_RELEASE"):
        with Path(release).open("r", encoding="utf-8") as source:
            assert source.readline() == "release\n"
    raise SystemExit(int(os.environ.get("LOCK_FIXTURE_MANAGER_STATUS", "0")))
else:
    message = "Unexpected fixture command"
    raise SystemExit(message)
