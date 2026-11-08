"""Reconcile the persisted AudioMuse server endpoint through its supported API."""

# API JSON is dynamic; errors contain fixed operator diagnostics, never secrets.
# ruff: file-ignore[raise-vanilla-args, raw-string-in-exception]

from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path
from typing import TYPE_CHECKING, Any, NoReturn, override

if TYPE_CHECKING:
    from collections.abc import Callable
from urllib.request import HTTPRedirectHandler, Request, build_opener


class NoRedirect(HTTPRedirectHandler):
    """Keep the API credential on the loopback endpoint."""

    @override
    def redirect_request(self, *args: object, **kwargs: object) -> NoReturn:
        """Reject redirects.

        Raises:
            OSError: Always, before credentials can leave the origin.

        """
        raise OSError("Unexpected redirect from the local AudioMuse API")


def reconcile(request: Callable[..., dict[str, Any]], desired_url: str) -> bool:
    """Probe before saving a changed endpoint, preserving other settings.

    Returns:
        Whether an endpoint update was saved.

    Raises:
        RuntimeError: The endpoint is absent or its connection probe fails.

    """
    current = request("/api/setup")
    fields = current.get("basic_fields", []) + current.get("advanced_fields", [])
    values = {field["name"]: field.get("value") for field in fields}
    if "NAVIDROME_URL" not in values:
        raise RuntimeError("AudioMuse setup does not expose its Navidrome endpoint")
    if values["NAVIDROME_URL"].rstrip("/") == desired_url.rstrip("/"):
        return False
    update = {"config": {"NAVIDROME_URL": desired_url}}
    probe = request("/api/setup", update | {"test_connection": True})
    if probe.get("status") != "ok":
        raise RuntimeError("AudioMuse could not verify its declared Navidrome endpoint")
    request("/api/setup", update)
    return True


def main() -> None:
    """Repair the local service and verify its persisted configuration.

    Raises:
        RuntimeError: The application does not return after saving settings.

    """
    token = (
        (Path(os.environ["CREDENTIALS_DIRECTORY"]) / "api-token").read_text().strip()
    )
    opener = build_opener(NoRedirect)

    def request(path: str, body: dict[str, Any] | None = None) -> dict[str, Any]:
        req = Request(
            "http://127.0.0.1:8000" + path,
            headers={
                "Authorization": "Bearer " + token,
                "Content-Type": "application/json",
            },
            data=json.dumps(body).encode() if body is not None else None,
        )
        with opener.open(req, timeout=20) as response:
            return json.load(response)

    changed = reconcile(request, sys.argv[1])
    if changed:
        # Saving settings restarts the application workers. Verify the persisted
        # endpoint after they return, without repeatedly POSTing during restart.
        deadline = time.monotonic() + 60
        while True:
            time.sleep(2)
            try:
                settings = request("/api/setup")
                values = {x["name"]: x.get("value") for x in settings["basic_fields"]}
                if values.get("NAVIDROME_URL", "").rstrip("/") == sys.argv[1].rstrip(
                    "/"
                ):
                    break
            except OSError, ValueError:  # ruff: ignore[try-except-pass]
                pass  # The application is restarting; the deadline bounds retries.
            if time.monotonic() >= deadline:
                raise RuntimeError(
                    "AudioMuse endpoint reconciliation did not become ready"
                )
    print(json.dumps({"changed": changed, "verified": True}))


if __name__ == "__main__":
    main()
