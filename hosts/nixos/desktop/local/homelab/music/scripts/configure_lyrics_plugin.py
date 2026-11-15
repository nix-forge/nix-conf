"""Enable the managed Navidrome lyrics plugin."""

import json
import os
import pathlib
import sys
import urllib.request
from typing import Any

base = "http://127.0.0.1:@toString_navidromePort@"


def request(
    path: str, method: str, payload: dict[str, object], token: str | None = None
) -> Any:
    """Send a bounded request to the configured loopback service.

    Returns:
        The JSON response, or None for an empty response body.

    """
    headers = {"Content-Type": "application/json"}
    if token:
        headers["X-ND-Authorization"] = "Bearer " + token
    req = urllib.request.Request(
        base + path,
        data=json.dumps(payload).encode(),
        method=method,
        headers=headers,
    )
    with urllib.request.urlopen(req, timeout=15) as response:
        body = response.read()
        return json.loads(body) if body else None


login = request(
    "/auth/login",
    "POST",
    {
        "username": os.environ["NAVIDROME_ADMIN_USERNAME"],
        "password": os.environ["NAVIDROME_ADMIN_PASSWORD"],
    },
)
token = login["token"]
request("/api/plugin/rescan", "POST", {}, token)
plugin = request(
    "/api/plugin/nd-lyrics",
    "PUT",
    {
        "config": pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"),
        "allUsers": True,
        "allLibraries": True,
        "allowWriteAccess": False,
        "enabled": True,
    },
    token,
)
if not plugin or plugin.get("enabled") is not True:
    msg = "Navidrome did not enable the lyrics plugin"
    raise RuntimeError(msg)
