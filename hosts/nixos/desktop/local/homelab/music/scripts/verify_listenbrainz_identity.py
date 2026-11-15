"""Validate the sealed ListenBrainz token inside the VPN before account mutation."""

# Only fixed diagnostics are raised; provider responses and tokens are never printed.
# ruff: file-ignore[raise-vanilla-args, raw-string-in-exception]

from __future__ import annotations

import hashlib
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import NoReturn, override


class NoRedirect(urllib.request.HTTPRedirectHandler):
    """Do not forward the token to another origin."""

    @override
    def redirect_request(self, *args: object, **kwargs: object) -> NoReturn:
        """Reject redirects before forwarding a credential.

        Raises:
            OSError: Always; redirects are not permitted.

        """
        raise OSError("Unexpected redirect from ListenBrainz")


def token_identity(token: str) -> tuple[bool, str]:
    """Read the provider's non-mutating identity response over verified HTTPS.

    Returns:
        The validation status and the confirmed provider account name.

    """
    request = urllib.request.Request(
        "https://api.listenbrainz.org/1/validate-token",
        headers={"Authorization": "Token " + token},
    )
    with urllib.request.build_opener(NoRedirect()).open(
        request, timeout=10
    ) as response:
        value = json.load(response)
        if not isinstance(value, dict):
            return False, ""
        username = value.get("user_name")
        return value.get("valid") is True, username if isinstance(username, str) else ""


def verify(credentials: Path, receipt: Path) -> None:
    """Publish only a confirmed identity fingerprint; stale receipts fail closed.

    Raises:
        RuntimeError: The provider rejects the token or confirms another owner.

    """
    receipt.unlink(missing_ok=True)
    identity = json.loads(credentials.read_text(encoding="utf-8"))
    token = str(identity.get("token") or "").strip()
    username = str(identity.get("listenbrainzUsername") or "").strip()
    if not token:
        return
    valid, owner = token_identity(token)
    if not username or not valid or owner != username:
        raise RuntimeError(
            "ListenBrainz token owner did not match the configured account"
        )
    fingerprint = hashlib.sha256((username + "\0" + token).encode()).hexdigest()
    payload = json.dumps({"username": username, "fingerprint": fingerprint}) + "\n"
    descriptor = os.open(receipt, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o400)
    with os.fdopen(descriptor, "w") as output:
        output.write(payload)
        output.flush()
        os.fsync(output.fileno())


if __name__ == "__main__":
    try:
        verify(
            Path(os.environ["CREDENTIALS_DIRECTORY"]) / "listenbrainz-identity",
            Path(sys.argv[1]),
        )
    except OSError, ValueError, KeyError, RuntimeError, urllib.error.HTTPError:
        sys.stderr.write("ListenBrainz identity validation failed\n")
        sys.exit(1)
