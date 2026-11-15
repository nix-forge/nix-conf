"""Reconcile a dedicated Actual realm using runtime credentials only."""

import json
import os
import pathlib
import sys
import urllib.error
import urllib.parse
import urllib.request
from http import HTTPStatus
from typing import Any


def main() -> None:
    """Create the private realm, account and confidential OIDC client.

    Raises:
        RuntimeError: An existing identity is ambiguous.
        urllib.error.HTTPError: The identity provider rejects a request.

    """
    credentials = pathlib.Path(os.environ["CREDENTIALS_DIRECTORY"])

    def read(name: str) -> str:
        return (credentials / name).read_text(encoding="utf-8").strip()

    admin = dict(
        line.split("=", 1) for line in read("admin").splitlines() if "=" in line
    )
    base = sys.argv[1].rstrip("/")
    origin = sys.argv[2].rstrip("/")
    form = urllib.parse.urlencode({
        "grant_type": "password",
        "client_id": "admin-cli",
        "username": admin["HOMELAB_ADMIN_USERNAME"],
        "password": admin["HOMELAB_ADMIN_PASSWORD"],
    }).encode()
    with urllib.request.urlopen(
        urllib.request.Request(
            base + "/realms/master/protocol/openid-connect/token", data=form
        ),
        timeout=30,
    ) as response:
        token = json.load(response)["access_token"]

    def request(method: str, path: str, data: dict[str, Any] | None = None) -> Any:
        body = json.dumps(data).encode() if data is not None else None
        req = urllib.request.Request(
            base + "/admin" + path,
            data=body,
            method=method,
            headers={
                "Authorization": "Bearer " + token,
                "Content-Type": "application/json",
            },
        )
        with urllib.request.urlopen(req, timeout=30) as response:
            content = response.read()
            return json.loads(content) if content else None

    try:
        request("GET", "/realms/actual")
    except urllib.error.HTTPError as error:
        if error.code != HTTPStatus.NOT_FOUND:
            raise
        request(
            "POST",
            "/realms",
            {
                "realm": "actual",
                "enabled": True,
                "sslRequired": "external",
                "registrationAllowed": False,
                "resetPasswordAllowed": False,
                "bruteForceProtected": True,
                "failureFactor": 5,
                "waitIncrementSeconds": 60,
                "maxFailureWaitSeconds": 900,
            },
        )
    username = read("username")
    users = request(
        "GET",
        "/realms/actual/users?"
        + urllib.parse.urlencode({"username": username, "exact": "true"}),
    )
    if not users:
        request(
            "POST",
            "/realms/actual/users",
            {
                "username": username,
                "firstName": "Budget",
                "lastName": "Owner",
                "email": "owner@localhost.invalid",
                "enabled": True,
                "emailVerified": True,
                "credentials": [
                    {"type": "password", "value": read("password"), "temporary": False}
                ],
            },
        )
    elif len(users) != 1:
        raise RuntimeError("Ambiguous Actual identity; refusing to change accounts")
    # Existing passwords are deliberately not reset on every restart.
    clients = request("GET", "/realms/actual/clients?clientId=actual")
    client = {
        "clientId": "actual",
        "enabled": True,
        "protocol": "openid-connect",
        "publicClient": False,
        "secret": read("client-secret"),
        "standardFlowEnabled": True,
        "directAccessGrantsEnabled": False,
        "serviceAccountsEnabled": False,
        "redirectUris": [origin + "/openid/callback"],
        "webOrigins": [origin],
        "attributes": {"pkce.code.challenge.method": "S256"},
        "defaultClientScopes": ["web-origins", "profile", "email", "roles"],
    }
    if clients:
        if len(clients) != 1:
            raise RuntimeError("Ambiguous Actual client")
        request("PUT", "/realms/actual/clients/" + clients[0]["id"], client)
    else:
        request("POST", "/realms/actual/clients", client)
    print("Actual identity configuration ready")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # HTTP exceptions can include sensitive URLs or response content.
        print(
            "Actual identity reconciliation failed; credentials were not logged",
            file=sys.stderr,
        )
        sys.exit(1)
