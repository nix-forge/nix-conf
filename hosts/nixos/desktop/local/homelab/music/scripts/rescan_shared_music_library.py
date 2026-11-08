"""Queue a shared music library scan when no scan is already running."""

import json
import os
import pathlib
import subprocess  # ruff: ignore[suspicious-subprocess-import] - fixed curl command, notification-based process wait
import urllib.request

from notification_process import run

credentials = pathlib.Path(os.environ["CREDENTIALS_DIRECTORY"])
key = (credentials / "lidarr-api-key").read_text().strip()
base = os.environ["LIDARR_URL"] + "/api/v1"
headers = {"X-Api-Key": key, "Content-Type": "application/json"}
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
# Only the idempotent read is retried: service ordering does not guarantee that
# Lidarr has opened its HTTP listener. curl owns bounded protocol backoff.
request_timeout = int(os.environ["HTTP_TIMEOUT_SECONDS"])
retry_budget = int(os.environ["HTTP_RETRY_BUDGET_SECONDS"])
retry_attempts = int(os.environ["HTTP_RETRY_ATTEMPTS"])
if request_timeout <= 0 or retry_budget <= 0 or retry_attempts < 0:
    message = "HTTP deadlines must be positive and retries nonnegative"
    raise ValueError(message)
if "\r" in key or "\n" in key:
    message = "API keys cannot contain header line breaks"
    raise ValueError(message)
response = run(
    [
        os.environ["CURL"],
        "--silent",
        "--show-error",
        "--fail",
        "--noproxy",
        "*",
        "--max-time",
        str(request_timeout),
        "--retry",
        str(retry_attempts),
        "--retry-connrefused",
        "--retry-max-time",
        str(retry_budget),
        "--header",
        "@-",
        base + "/command",
    ],
    input=("X-Api-Key: " + key + "\n").encode(),
    stdout=subprocess.PIPE,
    timeout=retry_budget + request_timeout + 5,
    check=True,
)
commands = json.loads(response.stdout)
scanning = any(
    command.get("name") == "RescanFolders"
    and command.get("status") in {"queued", "started"}
    for command in commands
)
if not scanning:
    payload = {"name": "RescanFolders", "folders": [os.environ["MUSIC_ROOT"]]}
    request = urllib.request.Request(
        base + "/command", data=json.dumps(payload).encode(), headers=headers
    )
    with opener.open(request, timeout=request_timeout):
        print("Shared music library rescan queued")
