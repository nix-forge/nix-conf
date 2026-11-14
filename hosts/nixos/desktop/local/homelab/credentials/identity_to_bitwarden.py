#!/usr/bin/env python3
"""Create sealed identity credentials and copy the password logins into Bitwarden."""

import argparse
import base64
import importlib.util
import json
import os
import secrets
import shlex
import stat
import sys
import urllib.parse
from pathlib import Path

# Share the established SSH seal transport and conservative vault item writer.
_spec = importlib.util.spec_from_file_location(
    "credential_transport", Path(__file__).with_name("miniflux_to_bitwarden.py")
)
if _spec is None or _spec.loader is None:
    raise RuntimeError("Credential transport module is unavailable")
transport = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(transport)

REVEAL = (
    Path(__file__).with_name("identity_reveal_worker.py").read_text(encoding="utf-8")
)


def existing(args: argparse.Namespace, plan: dict, name: str) -> str | None:
    """Reveal an existing encrypted bundle through the administrator SSH host.

    Returns:
        The decrypted value, or None when the canonical file is absent.

    """
    key = transport.secret_id(plan, name)
    source = plan["secrets"][key]["source"]
    path = args.repo_root / source
    if not path.exists():
        return None
    request = {
        "plan": plan,
        "secret": key,
        "source": source,
        "identity": args.identity,
        "ciphertext": base64.b64encode(path.read_bytes()).decode(),
    }
    return transport.run(
        [
            "ssh",
            "-o",
            "BatchMode=yes",
            args.administrator_host,
            "python3 -c " + shlex.quote(REVEAL),
        ],
        input_text=json.dumps(request),
    )


def realm_document(
    name: str,
    origin: str,
    identity_origin: str,
    username: str,
    password: str,
    client_secret: str,
) -> dict:
    """Build an encrypted realm with password login and optional passkey enrollment.

    Returns:
        The realm import document.

    """
    return {
        "realm": name,
        "enabled": True,
        "registrationAllowed": False,
        "resetPasswordAllowed": False,
        "verifyEmail": False,
        "rememberMe": True,
        "bruteForceProtected": True,
        "permanentLockout": False,
        "failureFactor": 5,
        "webAuthnPolicyPasswordlessPasskeysEnabled": True,
        "webAuthnPolicyPasswordlessMediation": "conditional",
        "webAuthnPolicyPasswordlessResidentKey": "required",
        "webAuthnPolicyPasswordlessUserVerificationRequirement": "required",
        "webAuthnPolicyPasswordlessRpId": identity_origin.split("://", 1)[1],
        "users": [
            {
                "username": username,
                "enabled": True,
                "email": username + "@" + identity_origin.split("://", 1)[1],
                "emailVerified": True,
                "firstName": "Home",
                "lastName": "Member",
                "requiredActions": [],
                # Imported users need explicit native self-service roles.
                # Otherwise Account Console tokens cannot access credentials.
                "clientRoles": {"account": ["manage-account", "view-profile"]},
                "credentials": [
                    {"type": "password", "value": password, "temporary": False}
                ],
            }
        ],
        "clients": [
            {
                "clientId": "wardrowbe",
                "enabled": True,
                "protocol": "openid-connect",
                "publicClient": False,
                "clientAuthenticatorType": "client-secret",
                "secret": client_secret,
                "standardFlowEnabled": True,
                "implicitFlowEnabled": False,
                "directAccessGrantsEnabled": False,
                "serviceAccountsEnabled": False,
                "redirectUris": [origin + "/api/auth/callback/oidc"],
                "webOrigins": [origin],
                "defaultClientScopes": [
                    "basic",
                    "profile",
                    "email",
                    "roles",
                    "web-origins",
                    "acr",
                ],
                "attributes": {
                    "pkce.code.challenge.method": "S256",
                    "post.logout.redirect.uris": origin,
                },
            }
        ],
    }


def origin(value: str) -> str:
    """Validate a credential-free HTTPS origin.

    Returns:
        The origin without a trailing slash.

    Raises:
        ValueError: The URL is not an HTTPS origin.

    """
    parsed = urllib.parse.urlsplit(value)
    if (
        parsed.scheme != "https"
        or not parsed.hostname
        or any([parsed.username is not None, parsed.password is not None])
        or parsed.path not in {"", "/"}
        or any([parsed.query, parsed.fragment])
    ):
        raise ValueError("Expected a credential-free HTTPS origin")
    return value.rstrip("/")


def main() -> None:
    """Create missing ciphertext and export matching vault entries.

    Raises:
        RuntimeError: The private session file or existing migration is unsafe.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("plan", "bootstrap-plan", "session-file"):
        parser.add_argument("--" + name, type=Path, required=True)
    for name in (
        "identity",
        "authorizer-key",
        "administrator-host",
        "identity-url",
        "wardrobe-url",
    ):
        parser.add_argument("--" + name, required=True)
    parser.add_argument("--realm", default="homelab")
    parser.add_argument(
        "--repo-root", type=Path, default=Path(__file__).resolve().parents[6]
    )
    args = parser.parse_args()
    args.identity_url = origin(args.identity_url)
    args.wardrobe_url = origin(args.wardrobe_url)
    mode = args.session_file.lstat()
    if (
        not stat.S_ISREG(mode.st_mode)
        or mode.st_uid != os.getuid()
        or mode.st_mode & 0o077
    ):
        raise RuntimeError(
            "Bitwarden session file must be a private regular file owned by this user"
        )
    os.environ["BW_SESSION"] = args.session_file.read_text().strip()
    transport.require_unlocked_bitwarden()
    plan = json.loads(args.plan.read_text())
    bootstrap = json.loads(args.bootstrap_plan.read_text())
    values = {}
    for name in (
        "homelab-identity-realm",
        "homelab-identity-admin-env",
        "homelab-wardrowbe-env",
    ):
        values[name] = (
            existing(args, plan, name)
            if any(k.endswith("/" + name) for k in plan["secrets"])
            else None
        )
    if not values["homelab-identity-realm"]:
        if values["homelab-wardrowbe-env"]:
            raise RuntimeError(
                "Existing application credentials require an explicit migration"
            )
        values["homelab-identity-realm"] = json.dumps(
            realm_document(
                args.realm,
                args.wardrobe_url,
                args.identity_url,
                "member",
                secrets.token_urlsafe(32),
                secrets.token_urlsafe(48),
            )
        )
    realm = json.loads(values["homelab-identity-realm"])
    if not values["homelab-identity-admin-env"]:
        values["homelab-identity-admin-env"] = "\n".join([
            "KC_BOOTSTRAP_ADMIN_USERNAME=bootstrap",
            "KC_BOOTSTRAP_ADMIN_PASSWORD=" + secrets.token_urlsafe(32),
            "HOMELAB_ADMIN_USERNAME=administrator",
            "HOMELAB_ADMIN_PASSWORD=" + secrets.token_urlsafe(32),
            "",
        ])
    if not values["homelab-wardrowbe-env"]:
        values["homelab-wardrowbe-env"] = "\n".join([
            "OIDC_CLIENT_ID=" + realm["clients"][0]["clientId"],
            "OIDC_CLIENT_SECRET=" + realm["clients"][0]["secret"],
            "SECRET_KEY=" + secrets.token_urlsafe(48),
            "NEXTAUTH_SECRET=" + secrets.token_urlsafe(48),
            "",
        ])
    for name, value in values.items():
        key = transport.secret_id(
            plan if any(k.endswith("/" + name) for k in plan["secrets"]) else bootstrap,
            name,
        )
        transport.seal(
            args.plan,
            args.bootstrap_plan,
            plan,
            bootstrap,
            args.identity,
            args.authorizer_key,
            key,
            value,
            args.repo_root,
            args.administrator_host,
        )
    account = realm["users"][0]
    transport.bitwarden_login(
        "Wardrowbe",
        args.identity_url,
        account["username"],
        account["credentials"][0]["value"],
    )
    admin = dict(
        line.split("=", 1)
        for line in values["homelab-identity-admin-env"].splitlines()
        if "=" in line
    )
    transport.bitwarden_login(
        "Wardrowbe sign-in administrator",
        args.identity_url + "/admin/",
        admin["HOMELAB_ADMIN_USERNAME"],
        admin["HOMELAB_ADMIN_PASSWORD"],
    )
    args.session_file.unlink()
    os.environ.pop("BW_SESSION", None)
    print(
        "Identity credentials sealed; both Bitwarden items synced; temporary unlock file removed"
    )


if __name__ == "__main__":
    try:
        main()
    except OSError, RuntimeError, ValueError, KeyError:
        print(
            "Identity credential setup failed; sensitive output suppressed",
            file=sys.stderr,
        )
        sys.exit(1)
