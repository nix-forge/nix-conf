"""Link the managed listener to its ListenBrainz account."""

import json
import pathlib
import sys
import urllib.request
from typing import Any

account = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
password = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8").strip()
username = sys.argv[3] if len(sys.argv) > 3 else account["navidromeUsername"]
base = "http://127.0.0.1:@toString_navidromePort@"


def request(
    path: str,
    method: str,
    payload: dict[str, object],
    headers: dict[str, str] | None = None,
) -> Any:
    """Send a bounded request to the configured loopback service.

    Returns:
        The JSON response, or None for an empty response body.

    """
    body = json.dumps(payload).encode()
    req = urllib.request.Request(
        base + path,
        data=body,
        method=method,
        headers={"Content-Type": "application/json", **(headers or {})},
    )
    with urllib.request.urlopen(req, timeout=15) as response:
        return json.load(response)


try:
    login = request(
        "/auth/login",
        "POST",
        {"username": username, "password": password},
    )
    linked = request(
        "/api/listenbrainz/link",
        "PUT",
        {"token": account["token"]},
        {"X-ND-Authorization": "Bearer " + login["token"]},
    )
    if (
        linked.get("status") is not True
        or linked.get("user") != account["listenbrainzUsername"]
    ):
        msg = "ListenBrainz account mismatch"
        raise ValueError(msg)
except Exception:
    print(
        "Unable to link ListenBrainz scrobbling for the managed listener",
        file=sys.stderr,
    )
    sys.exit(1)
