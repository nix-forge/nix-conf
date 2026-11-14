#!/usr/bin/env python3
"""Seal the live Miniflux login and save its login in Bitwarden."""

from __future__ import annotations

import argparse
import base64
import getpass
import json
import os
import shlex
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from collections.abc import Mapping

DOMAIN = json.loads(
    (Path(__file__).resolve().parents[5] / "shared/local/network.json").read_text(
        encoding="utf-8"
    )
)["homelabDomain"]
URL = f"https://miniflux.{DOMAIN}"
RUNTIME_FILE = Path("/var/lib/homelab-miniflux/admin.env")

# This worker runs on the administrator Mac. It receives plaintext only over
# SSH stdin and writes only public plans and encrypted output to temporary disk.
REMOTE_SEAL_WORKER = (
    Path(__file__).with_name("miniflux_seal_worker.py").read_text(encoding="utf-8")
)


def run(
    args: list[str],
    *,
    input_text: str | None = None,
    env: Mapping[str, str] | None = None,
) -> str:
    """Run an operator command without exposing its captured secret output.

    Returns:
        The command's standard output.

    """
    result = subprocess.run(
        args, input=input_text, text=True, capture_output=True, env=env, check=False
    )
    if result.returncode:
        raise RuntimeError(
            f"{args[0]} failed (exit {result.returncode}); no secret output shown"
        )
    return result.stdout


def read_credential(prompt: bool, credential_via_host: str | None) -> tuple[str, str]:
    """Read the existing login interactively or through the selected host.

    Returns:
        The verified nonempty username and password.

    """
    if prompt:
        username = input("Existing Miniflux username [admin]: ").strip() or "admin"
        password = getpass.getpass("Existing Miniflux password: ")
    else:
        if credential_via_host:
            raw = run([
                "ssh",
                "-o",
                "BatchMode=yes",
                credential_via_host,
                "ssh -o BatchMode=yes root@desktop cat "
                + shlex.quote(str(RUNTIME_FILE)),
            ])
        else:
            raw = run(["sudo", "cat", str(RUNTIME_FILE)])
        values = {}
        for line in raw.splitlines():
            key, separator, value = line.partition("=")
            if separator and key in {"ADMIN_USERNAME", "ADMIN_PASSWORD"}:
                values[key] = value
        username = values.get("ADMIN_USERNAME", "")
        password = values.get("ADMIN_PASSWORD", "")
    if not username or not password or any(c in username + password for c in "\r\n\0"):
        raise RuntimeError("Missing or invalid Miniflux credential")
    return username, password


def verify_login(username: str, password: str) -> None:
    """Check that HTTPS authenticates the expected Miniflux account."""
    token = base64.b64encode(f"{username}:{password}".encode()).decode()
    request = urllib.request.Request(
        URL + "/v1/me", headers={"Authorization": "Basic " + token}
    )
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            account = json.load(response)
    except (urllib.error.URLError, ValueError) as error:
        raise RuntimeError(
            "Miniflux rejected the credential or HTTPS verification failed"
        ) from error
    if account.get("username") != username:
        raise RuntimeError("Miniflux returned a different account")


def secret_id(plan: dict[str, Any], local_name: str) -> str:
    """Find the unique secret entry with the requested source name.

    Returns:
        The complete plan secret identifier.

    """
    matches = [
        key
        for key in plan["secrets"]
        if key.endswith("/" + local_name)
        and plan["secrets"][key]["source"].endswith("/" + local_name + ".age")
    ]
    if len(matches) != 1:
        raise RuntimeError(f"Expected exactly one plan secret for {local_name}")
    return matches[0]


def remote_seal(
    host: str,
    operation: str,
    plan: dict[str, Any],
    source: str,
    secret: str,
    identity: str | Path,
    authorizer_key: str | Path | None,
    value: str,
    ciphertext: bytes | None = None,
) -> str:
    """Send one credential operation through the administrator's SSH stdin.

    Returns:
        The sanitized comparison result or encoded ciphertext.

    """
    request = {
        "operation": operation,
        "plan": plan,
        "source": source,
        "secret": secret,
        "identity": str(identity),
        "authorizer_key": str(authorizer_key),
        "value": value,
    }
    if ciphertext is not None:
        request["ciphertext"] = base64.b64encode(ciphertext).decode()
    return run(
        [
            "ssh",
            "-o",
            "BatchMode=yes",
            host,
            "python3 -c " + shlex.quote(REMOTE_SEAL_WORKER),
        ],
        input_text=json.dumps(request),
    )


def seal(
    plan_path: Path,
    bootstrap_path: Path | None,
    normal_plan: dict[str, Any],
    bootstrap_plan: dict[str, Any],
    identity: str | Path,
    authorizer_key: str | Path | None,
    secret: str,
    value: str,
    repo_root: Path,
    administrator_host: str | None,
) -> None:
    """Create a missing encrypted secret or verify that its value matches."""
    source = (
        normal_plan["secrets"].get(secret) or bootstrap_plan["secrets"].get(secret)
    )["source"]
    exists = (repo_root / source).exists()
    selected_plan = plan_path if exists else bootstrap_path
    if selected_plan is None:
        raise RuntimeError(f"Missing bootstrap plan for {secret}")
    args = [
        "nix-seal",
        "secret",
        "bootstrap",
        "complete",
        "--bootstrap-plan",
        str(selected_plan),
        "--repository-root",
        str(repo_root),
        "--secret",
        secret,
        "--authorizer-key",
        str(authorizer_key),
    ]
    if exists:
        if administrator_host:
            same = (
                remote_seal(
                    administrator_host,
                    "compare",
                    normal_plan,
                    source,
                    secret,
                    identity,
                    authorizer_key,
                    value,
                    (repo_root / source).read_bytes(),
                )
                == "match"
            )
        else:
            existing = run([
                "nix-seal",
                "secret",
                "reveal",
                "--plan",
                str(plan_path),
                "--repository-root",
                str(repo_root),
                "--secret",
                secret,
                "--identity",
                str(identity),
            ])
            same = existing == value
        if not same:
            raise RuntimeError(
                f"Existing sealed secret {secret} differs from the live login"
            )
        print(f"Sealed secret {secret} already matches")
    else:
        if not authorizer_key:
            raise RuntimeError("Creating a missing secret requires --authorizer-key")
        if administrator_host:
            encoded = remote_seal(
                administrator_host,
                "create",
                bootstrap_plan,
                source,
                secret,
                identity,
                authorizer_key,
                value,
            )
            destination = repo_root / source
            destination.parent.mkdir(parents=True, exist_ok=True)
            descriptor = os.open(
                destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600
            )
            with os.fdopen(descriptor, "wb") as output:
                output.write(base64.b64decode(encoded, validate=True))
        else:
            run(args, input_text=value)
        print(f"Created sealed secret {secret}")


def bitwarden_login(name: str, url: str, username: str, password: str) -> None:
    """Create or update the matching login while preserving passkey entries."""
    environment = os.environ.copy()
    if not environment.get("BW_SESSION"):
        raise RuntimeError(
            'Unlock Bitwarden first: export BW_SESSION="$(bw unlock --raw)"'
        )
    status = json.loads(run(["bw", "status"], env=environment))
    if status.get("status") != "unlocked":
        raise RuntimeError("Bitwarden is locked; unlock it before running this script")
    run(["bw", "sync"], env=environment)
    candidates = json.loads(
        run(["bw", "list", "items", "--search", name], env=environment)
    )
    matches = [
        item
        for item in candidates
        if any(
            uri.get("uri", "").rstrip("/") == url
            for uri in item.get("login", {}).get("uris", [])
        )
    ]
    if len(matches) > 1:
        raise RuntimeError(
            "Multiple Bitwarden logins use this URL; resolve duplicates first"
        )
    if matches:
        item = matches[0]
        if item["login"].get("username") not in {None, "", username}:
            raise RuntimeError("Bitwarden has this URL with a different username")
        if (
            item["login"].get("username") == username
            and item["login"].get("password") == password
        ):
            print(f"Bitwarden {name} login already matches")
            return
        if item["login"].get("fido2Credentials"):
            raise RuntimeError(
                "This Bitwarden item already has a passkey; "
                "update its password in Bitwarden manually"
            )
        item["login"]["username"] = username
        item["login"]["password"] = password
        operation = ["bw", "edit", "item", item["id"]]
    else:
        item = json.loads(run(["bw", "get", "template", "item"], env=environment))
        item["type"] = 1
        item["name"] = name
        item["login"] = {
            "username": username,
            "password": password,
            "uris": [{"uri": url, "match": 0}],
        }
        operation = ["bw", "create", "item"]
    payload = base64.b64encode(json.dumps(item).encode()).decode()
    run(operation, input_text=payload, env=environment)
    run(["bw", "sync"], env=environment)
    print(f"Bitwarden {name} login saved and synced")


def require_unlocked_bitwarden() -> None:
    """Check Bitwarden's actual unlock state before reading credentials."""
    if not os.environ.get("BW_SESSION"):
        raise RuntimeError(
            'Unlock Bitwarden first: export BW_SESSION="$(bw unlock --raw)"'
        )
    status = json.loads(run(["bw", "status"], env=os.environ.copy()))
    if status.get("status") != "unlocked":
        raise RuntimeError("Bitwarden is locked; unlock it before running this script")


def main() -> None:
    """Verify the live login, then seal it and synchronize its vault entry."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--plan",
        type=Path,
        required=True,
        help="Compiled desktop nix-seal plan.v2 JSON",
    )
    parser.add_argument(
        "--bootstrap-plan", type=Path, help="Create-only plan for missing secrets"
    )
    parser.add_argument(
        "--identity",
        required=True,
        help="Administrator age private identity",
    )
    parser.add_argument(
        "--authorizer-key",
        help="Bootstrap authorizer signing key needed only for missing ciphertext",
    )
    parser.add_argument(
        "--administrator-host",
        help="SSH host that holds the private identity; keep the key on that host",
    )
    parser.add_argument(
        "--credential-via-host",
        help="SSH host that can read root@desktop's credential",
    )
    parser.add_argument(
        "--seal-only",
        action="store_true",
        help="Create or verify ciphertext now; import to Bitwarden on a later run",
    )
    parser.add_argument(
        "--repo-root", type=Path, default=Path(__file__).resolve().parents[6]
    )
    parser.add_argument(
        "--prompt",
        action="store_true",
        help="Ask for the current login instead of reading it with sudo",
    )
    args = parser.parse_args()
    if not args.plan.is_file():
        parser.error(f"Compiled plan is not a readable file: {args.plan}")
    if args.bootstrap_plan and not args.bootstrap_plan.is_file():
        parser.error(f"Bootstrap plan is not a readable file: {args.bootstrap_plan}")
    if not args.administrator_host and not Path(args.identity).is_file():
        parser.error(
            f"Administrator age identity is not a readable file: {args.identity}. "
            "Replace the example path with the actual private identity path."
        )
    plan = json.loads(args.plan.read_text())
    bootstrap = (
        json.loads(args.bootstrap_plan.read_text())
        if args.bootstrap_plan
        else {"secrets": {}}
    )
    combined = {"secrets": plan["secrets"] | bootstrap["secrets"]}
    username_id = secret_id(combined, "homelab-miniflux-username")
    password_id = secret_id(combined, "homelab-miniflux-password")
    if not args.seal_only:
        require_unlocked_bitwarden()
    username, password = read_credential(args.prompt, args.credential_via_host)
    verify_login(username, password)
    print("Existing Miniflux login verified over HTTPS")
    seal(
        args.plan,
        args.bootstrap_plan,
        plan,
        bootstrap,
        args.identity,
        args.authorizer_key,
        username_id,
        username,
        args.repo_root,
        args.administrator_host,
    )
    seal(
        args.plan,
        args.bootstrap_plan,
        plan,
        bootstrap,
        args.identity,
        args.authorizer_key,
        password_id,
        password,
        args.repo_root,
        args.administrator_host,
    )
    if args.seal_only:
        print(
            "Ciphertext is ready; rerun without --seal-only to save the Bitwarden login"
        )
        return
    bitwarden_login("Miniflux", URL, username, password)
    print(
        "Next: prepare and switch the desktop configuration, "
        "then enroll the passkey in Miniflux"
    )


if __name__ == "__main__":
    try:
        main()
    except (OSError, KeyError, RuntimeError, ValueError) as error:
        print(f"miniflux-to-bitwarden: {error}", file=sys.stderr)
        sys.exit(1)
