#!/usr/bin/env python3
"""Sync deployed, sealed homelab logins into Bitwarden without printing secrets."""

# This maintenance CLI deliberately invokes installed bw/ssh tools and reports
# sanitized errors. No shell invocation receives vault credentials.
# ruff: file-ignore[suspicious-subprocess-import, subprocess-without-shell-equals-true, start-process-with-partial-path, print, raise-vanilla-args, raw-string-in-exception, f-string-in-exception]

import argparse
import base64
import copy
import getpass
import json
import os
import shlex
import subprocess
import sys
import tempfile
from collections import defaultdict
from datetime import UTC, datetime
from pathlib import Path
from urllib.parse import urlsplit

BASE = "/run/nix-seal/system/services/current/ianhollow/hosts/nixos/desktop"
PI_BASE = "/run/nix-seal/system/services/current/ianhollow/hosts/nixos/raspberry-pi"
DOMAIN = json.loads(
    (Path(__file__).resolve().parents[5] / "shared/local/network.json").read_text(
        encoding="utf-8"
    )
)["homelabDomain"]
LEGACY_ACCOUNT_NAMES = {
    "Homelab identity": "Wardrowbe",
    "Homelab identity administrator": "Wardrowbe sign-in administrator",
}


def run(argv: list[str], *, data: str | None = None, env: dict | None = None) -> str:
    """Capture CLI output and report failure without exposing payloads.

    Returns:
        Captured stdout.

    Raises:
        RuntimeError: The operation failed validation or execution.

    """
    result = subprocess.run(
        argv, input=data, text=True, capture_output=True, env=env, check=False
    )
    if result.returncode:
        # Neither CLI output nor exception argv may expose a credential.
        raise RuntimeError(f"{argv[0]} operation failed (exit {result.returncode})")
    return result.stdout


def source_inventory() -> list[str]:
    """List every required runtime credential before changing the vault.

    Returns:
        Required sealed credential basenames.

    """
    return sorted({
        source for sources in account_sources().values() for source in sources
    })


def read_sources(host: str, names: list[str] | None = None) -> dict:
    """Read the deployed sealed files over the authorized SSH route.

    Returns:
        Decoded source values retained only in memory.

    """
    # Credentials travel on captured SSH stdout, never argv or temporary files.
    names = source_inventory() if names is None else names
    pi_names = [
        name
        for name in names
        if name.startswith(("homebridge-ui-", "homebridge-vesync-", "scrypted-ui-"))
    ]
    desktop_names = [name for name in names if name not in pi_names]
    return {
        **read_target_sources(host, "desktop", BASE, desktop_names),
        **read_target_sources(host, "raspberry-pi", PI_BASE, pi_names),
    }


def read_target_sources(host: str, target: str, base: str, names: list[str]) -> dict:
    """Read named runtime secrets through the administrator host.

    Returns:
        Decoded source values retained only in memory.

    Raises:
        RuntimeError: The operation failed validation or execution.

    """
    if not names:
        return {}
    remote = shlex.join(["bash", "-s", "--", base, *names])
    command = shlex.join(["ssh", "-o", "BatchMode=yes", f"root@{target}", remote])
    result = subprocess.run(
        ["ssh", "-o", "BatchMode=yes", "--", host, command],
        input=Path(__file__)
        .with_name("remote-read-sources.sh")
        .read_text(encoding="utf-8"),
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode:
        missing = [
            line.split("\t", 1)[1]
            for line in result.stdout.splitlines()
            if line.startswith("MISSING\t")
        ]
        if missing:
            raise RuntimeError(
                "Missing or ambiguous credential source: " + ", ".join(missing)
            )
        raise RuntimeError(
            "SSH credential inventory failed; check root access through the Mac"
        )
    output = result.stdout
    values = {}
    for line in output.splitlines():
        name, encoded = line.split("\t", 1)
        values[name] = base64.b64decode(encoded, validate=True).decode().rstrip("\n")
    missing = set(names) - values.keys()
    if missing:
        raise RuntimeError("Missing credential sources: " + ", ".join(sorted(missing)))
    return values


def dotenv(text: str) -> dict:
    """Parse literal dotenv values without evaluating shell expressions.

    Returns:
        Literal key-value pairs.

    Raises:
        RuntimeError: The operation failed validation or execution.

    """
    values = {}
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        key, sep, value = line.partition("=")
        if not sep:
            raise RuntimeError("Invalid deployed dotenv credential bundle")
        tokens = shlex.split(value, comments=False)
        values[key.removeprefix("export ")] = tokens[0] if len(tokens) == 1 else value
    return values


# ruff: ignore[complex-structure] (the inventory mirrors independently managed services)
def accounts(values: dict, only: set[str] | None = None) -> list[dict]:
    """Validate sources and construct the managed web-account inventory.

    Returns:
        Validated accounts with URI and credential fields.

    """
    values = defaultdict(str, values)
    result = []

    def add(
        name: str,
        app: str,
        username: str | None,
        password: str,
        explicit_url: str | None = None,
    ) -> None:
        if only and name not in only:
            return
        if (
            (username is not None and not username)
            or not password
            or any(c in (username or "") + password for c in "\r\n\0")
        ):
            raise RuntimeError(f"Missing or invalid deployed credential for {name}")
        url = (
            explicit_url
            if explicit_url is not None
            else (
                f"https://{app}.{DOMAIN}"
                if app != "audiomuse"
                else "http://127.0.0.1:8000"
            )
        )
        result.append({
            "name": name,
            "url": url,
            "username": username or "",
            "password": password,
        })

    for name, app, source in [
        ("FreshRSS", "freshrss", "freshrss"),
        ("Miniflux", "miniflux", "miniflux"),
        ("qBittorrent", "qbittorrent", "qbittorrent"),
        ("Aurral", "aurral", "aurral-admin"),
        ("Actual", "actual", "actual"),
    ]:
        add(
            name,
            app,
            values[f"homelab-{source}-username"],
            values[f"homelab-{source}-password"],
        )
    add(
        "Dashboard",
        "dashboard",
        None,  # Homepage asks only for a password.
        dotenv(values["homelab-dashboard-env"]).get("HOMEPAGE_AUTH_PASSWORD", ""),
    )
    add(
        "Stirling PDF",
        "pdf",
        values["homelab-stirling-admin-username"],
        values["homelab-stirling-admin-password"],
    )
    add(
        "Homebridge",
        "homebridge",
        values["homebridge-ui-username"],
        values["homebridge-ui-password"],
    )
    add(
        "VeSync (Homebridge)",
        "vesync",
        values["homebridge-vesync-username"],
        values["homebridge-vesync-password"],
        "https://account.vesync.com/",
    )
    add(
        "Scrypted",
        "scrypted",
        values["scrypted-ui-username"],
        values["scrypted-ui-password"],
    )
    for app in ("sonarr", "radarr", "lidarr", "prowlarr", "bazarr"):
        add(
            app.capitalize(),
            app,
            values[f"homelab-{app}-username"],
            values[f"homelab-{app}-password"],
        )
    for app in ("audiobookshelf", "komga"):
        for role in ("admin", "reader"):
            add(
                f"{app.capitalize()} ({role})",
                app,
                values[f"homelab-books-{app}-{role}-username"],
                values[f"homelab-books-{app}-{role}-password"],
            )
    add(
        "BookOrbit (admin)",
        "bookorbit",
        values["homelab-bookorbit-admin-username"],
        values["homelab-bookorbit-admin-password"],
    )
    for role in ("admin", "viewer"):
        for app in ("jellyfin", "seerr"):
            add(
                f"{app.capitalize()} ({role})",
                app,
                values[f"homelab-jellyfin-{role}-username"],
                values[f"homelab-jellyfin-{role}-password"],
            )
    navidrome = dotenv(values["music-discovery-navidrome-settings"])
    for role in ("admin", "service"):
        add(
            f"Navidrome ({role})",
            "navidrome",
            values[f"homelab-navidrome-{role}-username"],
            navidrome.get(f"NAVIDROME_{role.upper()}_PASSWORD", ""),
        )
    add(
        "Navidrome (listener)",
        "navidrome",
        values["homelab-navidrome-listener-username"],
        values["feishin-listener-password"],
    )
    identity = json.loads(values["music-discovery-listenbrainz-identity"] or "{}")
    add(
        "Navidrome (ListenBrainz)",
        "navidrome",
        identity.get("navidromeUsername", ""),
        values["music-discovery-listener-password"],
    )
    slskd = dotenv(values["music-discovery-slskd-settings"])
    add(
        "slskd",
        "slskd",
        slskd.get("SLSKD_USERNAME", ""),
        slskd.get("SLSKD_PASSWORD", ""),
    )
    muse = dotenv(values["music-discovery-audiomuse-settings"])
    add(
        "AudioMuse",
        "audiomuse",
        muse.get("AUDIOMUSE_USER", ""),
        muse.get("AUDIOMUSE_PASSWORD", ""),
    )
    realm = json.loads(values["homelab-identity-realm"] or "{}")
    realm_user = (realm.get("users") or [{}])[0]
    passwords = [
        credential.get("value", "")
        for credential in realm_user.get("credentials", [])
        if credential.get("type") == "password"
    ]
    add(
        "Wardrowbe",
        "identity",
        realm_user.get("username", ""),
        passwords[0] if len(passwords) == 1 else "",
    )
    administrator = dotenv(values["homelab-identity-admin-env"])
    add(
        "Wardrowbe sign-in administrator",
        "identity",
        administrator.get("HOMELAB_ADMIN_USERNAME", ""),
        administrator.get("HOMELAB_ADMIN_PASSWORD", ""),
        f"https://identity.{DOMAIN}/admin/",
    )
    add(
        "Indexer proxy (service)",
        "indexer-proxy",
        values["homelab-indexer-proxy-username"],
        values["homelab-indexer-proxy-password"],
        "",  # MicroSocks has no website URI for Bitwarden autofill.
    )
    return result


def matching_items(items: list[dict], account: dict) -> list[dict]:
    """Find login items by service URI or exact name for the URI-less proxy.

    Returns:
        Live login items for the requested account.

    """
    return [
        item
        for item in items
        if item.get("type") == 1
        and not item.get("deletedDate")
        and (
            (
                not account["url"]
                and item.get("name") == account["name"]
                and not (item.get("login") or {}).get("uris")
            )
            or any(
                uri.get("uri", "").rstrip("/") == account["url"].rstrip("/")
                for uri in (item.get("login") or {}).get("uris", [])
                if account["url"]
            )
        )
    ]


def matches_account_name(item: dict, account: dict) -> bool:
    """Match current and legacy vault titles.

    Returns:
        Whether the title identifies this account.

    """
    name = item.get("name")
    return LEGACY_ACCOUNT_NAMES.get(name, name) == account["name"]


def matches_username(item: dict, account: dict) -> bool:
    """Treat Bitwarden's null and empty password-only usernames alike.

    Returns:
        Whether the item and account have the same login username.

    """
    return (item["login"].get("username") or "") == account["username"]


def select_item(items: list[dict], account: dict) -> dict | None:
    """Resolve one matching account, including a safely named legacy login.

    Returns:
        The unique matching item, or None.

    Raises:
        RuntimeError: The operation failed validation or execution.

    """
    candidates = matching_items(items, account)
    same_account = [item for item in candidates if matches_username(item, account)]
    same_name = [item for item in candidates if matches_account_name(item, account)]
    selected = same_account or same_name
    if len(selected) > 1:
        raise RuntimeError(
            f"Ambiguous Bitwarden items for {account['name']}; resolve duplicates"
        )
    return selected[0] if selected else None


def reserve_item(claims: dict, account: dict, item: dict) -> None:
    """Reserve a vault item only for accounts with identical credentials.

    Raises:
        RuntimeError: Account labels share an item but require distinct credentials.

    """
    previous = claims.get(item["id"])
    if previous and (previous["username"], previous["password"]) != (
        account["username"],
        account["password"],
    ):
        raise RuntimeError(
            f"Conflicting Bitwarden item for {previous['name']} and {account['name']}: "
            "these accounts need separate vault entries; split the existing multi-service item and rerun"
        )
    claims[item["id"]] = account


def unique_item(items: list[dict], account: dict) -> dict | None:
    """Require a unique match before any vault mutation.

    Returns:
        The unique matching item, or None.

    Raises:
        RuntimeError: Duplicate matches require user review.

    """
    if len(items) > 1:
        raise RuntimeError(
            f"Ambiguous Bitwarden items for {account['name']}; resolve duplicate entries for this account"
        )
    return items[0] if items else None


def reserve_password_matches(
    items: list[dict], inventory: list[dict], claims: dict, exact: dict
) -> None:
    """Reserve unchanged-password identities whose custom names need migration."""
    for account in inventory:
        if account["name"] in exact:
            continue
        candidates = [
            item
            for item in matching_items(items, account)
            if item["id"] not in claims
            and item["login"].get("password") == account["password"]
        ]
        selected = unique_item(candidates, account)
        if selected:
            reserve_item(claims, account, selected)
            exact[account["name"]] = selected


def build_plan(
    items: list[dict], inventory: list[dict]
) -> list[tuple[dict, dict | None]]:
    """Reserve exact identities before resolving unclaimed legacy account names.

    Returns:
        A complete, conflict-checked account-to-item plan.

    """
    claims = {}
    exact = {}
    for account in inventory:
        matches = [
            item
            for item in matching_items(items, account)
            if matches_username(item, account)
        ]
        selected = unique_item(matches, account)
        if selected:
            reserve_item(claims, account, selected)
            exact[account["name"]] = selected
    reserve_password_matches(items, inventory, claims, exact)
    plan = []
    for account in inventory:
        selected = exact.get(account["name"])
        if not selected:
            candidates = [
                item
                for item in matching_items(items, account)
                if matches_account_name(item, account) and item["id"] not in claims
            ]
            selected = unique_item(candidates, account)
            if selected:
                reserve_item(claims, account, selected)
        plan.append((account, selected))
    return plan


def group_plan(
    plan: list[tuple[dict, dict | None]],
) -> list[tuple[list[dict], dict | None]]:
    """Group safely shared items so every item receives one merged mutation.

    Returns:
        Account groups with their shared existing item, if any.

    """
    groups = {}
    for account, item in plan:
        key = ("existing", item["id"]) if item else ("new", account["name"])
        group = groups.setdefault(key, ([], item))
        group[0].append(account)
    return list(groups.values())


def ensure_login_uri(uris: list, url: str, match: int) -> None:
    """Add or update a login URI without replacing its metadata."""
    existing = next(
        (uri for uri in uris if uri.get("uri", "").rstrip("/") == url.rstrip("/")), None
    )
    if existing is None:
        uris.append({"uri": url, "match": match})
    else:
        existing["match"] = match


def updated_item(item: dict | None, account: dict) -> dict:
    """Update login fields while retaining the rest of the vault item.

    Returns:
        A copied vault item with current login fields.

    """
    # Copy the complete item, including passkeys/TOTP/custom fields/folder.
    result: dict = (
        copy.deepcopy(item)
        if item
        else {"type": 1, "name": account["name"], "login": {}}
    )
    if matches_account_name(result, account):
        result["name"] = account["name"]
    login = result.setdefault("login", {})
    login.update(
        username=account["username"] or None,
        password=account["password"],
    )
    uris = login.setdefault("uris", [])
    match = (
        3
        if account["name"] == "Wardrowbe"
        else 2
        if account["name"] == "Wardrowbe sign-in administrator"
        else 1
    )
    if account["url"]:
        ensure_login_uri(uris, account["url"], match)
    if account["name"] == "Miniflux":
        # The news reader signs in with this sealed Miniflux account.
        reader_url = f"https://news.{DOMAIN}"
        ensure_login_uri(uris, reader_url, 1)
    if account["name"] == "Wardrowbe":
        realm_url = f"https://identity.{DOMAIN}/realms/homelab/"
        existing_realm = next(
            (uri for uri in uris if uri.get("uri") == realm_url), None
        )
        if existing_realm is None:
            uris.append({"uri": realm_url, "match": 2})
        else:
            existing_realm["match"] = 2
    if account["name"] == "Actual":
        actual_realm_url = f"https://identity.{DOMAIN}/realms/actual/"
        existing_actual_realm = next(
            (uri for uri in uris if uri.get("uri") == actual_realm_url), None
        )
        if existing_actual_realm is None:
            uris.append({"uri": actual_realm_url, "match": 2})
        else:
            existing_actual_realm["match"] = 2
    return result


def save_account(account: dict, item: dict | None, env: dict) -> str:
    """Send the encoded item through stdin and return only its identifier.

    Returns:
        The saved vault item identifier.

    """
    return save_accounts([account], item, env)


def save_accounts(group: list[dict], item: dict | None, env: dict) -> str:
    """Save a shared item once with every required service URI.

    Returns:
        The saved vault item identifier.

    """
    updated = item
    for account in group:
        updated = updated_item(updated, account)
    encoded = base64.b64encode(json.dumps(updated).encode()).decode()
    argv = ["bw", "edit", "item", item["id"]] if item else ["bw", "create", "item"]
    saved = json.loads(run(argv, data=encoded, env=env))
    return saved["id"]


def unlock(env: dict) -> None:
    """Unlock interactively without adding a master password to argv.

    Raises:
        RuntimeError: The operation failed validation or execution.

    """
    status = json.loads(run(["bw", "status"], env=env)).get("status")
    if status == "unauthenticated":
        raise RuntimeError("Sign in using bw login first")
    if status != "unlocked":
        if not sys.stdin.isatty():
            raise RuntimeError(
                "Run in your terminal to unlock Bitwarden, or export BW_SESSION"
            )
        unlocking = env.copy()
        unlocking["HOMELAB_BW_MASTER_PASSWORD"] = getpass.getpass(
            "Bitwarden master password: "
        )
        try:
            env["BW_SESSION"] = run(
                [
                    "bw",
                    "unlock",
                    "--raw",
                    "--passwordenv",
                    "HOMELAB_BW_MASTER_PASSWORD",
                ],
                env=unlocking,
            ).strip()
        finally:
            unlocking.pop("HOMELAB_BW_MASTER_PASSWORD", None)
    if json.loads(run(["bw", "status"], env=env)).get("status") != "unlocked":
        raise RuntimeError("Bitwarden remains locked")


def account_sources() -> dict:
    """Describe the source files needed for each selectable login.

    Returns:
        Account names mapped to credential basenames.

    """
    sources = {}
    for name, source in [
        ("FreshRSS", "freshrss"),
        ("Miniflux", "miniflux"),
        ("qBittorrent", "qbittorrent"),
        ("Aurral", "aurral-admin"),
        ("Actual", "actual"),
    ]:
        sources[name] = [f"homelab-{source}-username", f"homelab-{source}-password"]
    for app in ("sonarr", "radarr", "lidarr", "prowlarr", "bazarr"):
        sources[app.capitalize()] = [
            f"homelab-{app}-username",
            f"homelab-{app}-password",
        ]
    for app in ("audiobookshelf", "komga"):
        for role in ("admin", "reader"):
            sources[f"{app.capitalize()} ({role})"] = [
                f"homelab-books-{app}-{role}-username",
                f"homelab-books-{app}-{role}-password",
            ]
    sources["BookOrbit (admin)"] = [
        "homelab-bookorbit-admin-username",
        "homelab-bookorbit-admin-password",
    ]
    for role in ("admin", "viewer"):
        for app in ("jellyfin", "seerr"):
            sources[f"{app.capitalize()} ({role})"] = [
                f"homelab-jellyfin-{role}-username",
                f"homelab-jellyfin-{role}-password",
            ]
    for role in ("admin", "service"):
        sources[f"Navidrome ({role})"] = [
            f"homelab-navidrome-{role}-username",
            "music-discovery-navidrome-settings",
        ]
    sources["Navidrome (listener)"] = [
        "homelab-navidrome-listener-username",
        "feishin-listener-password",
    ]
    sources["Navidrome (ListenBrainz)"] = [
        "music-discovery-listenbrainz-identity",
        "music-discovery-listener-password",
    ]
    sources["slskd"] = ["music-discovery-slskd-settings"]
    sources["AudioMuse"] = ["music-discovery-audiomuse-settings"]
    sources["Wardrowbe"] = ["homelab-identity-realm"]
    sources["Wardrowbe sign-in administrator"] = ["homelab-identity-admin-env"]
    sources["Stirling PDF"] = [
        "homelab-stirling-admin-username",
        "homelab-stirling-admin-password",
    ]
    sources["Dashboard"] = ["homelab-dashboard-env"]
    sources["Homebridge"] = ["homebridge-ui-username", "homebridge-ui-password"]
    sources["VeSync (Homebridge)"] = [
        "homebridge-vesync-username",
        "homebridge-vesync-password",
    ]
    sources["Scrypted"] = ["scrypted-ui-username", "scrypted-ui-password"]
    sources["Indexer proxy (service)"] = [
        "homelab-indexer-proxy-username",
        "homelab-indexer-proxy-password",
    ]
    return sources


def write_receipt(path: Path, saved: list[tuple[dict, str]]) -> None:
    """Atomically retain a private verification receipt containing no credentials."""
    path = path.expanduser()
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    timestamp = datetime.now(UTC).isoformat()
    previous = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    entries = {
        record["name"]: {
            "name": record["name"],
            "itemId": record["itemId"],
            "verified": record["verified"],
            "verifiedAt": record.get("verifiedAt", previous.get("verifiedAt")),
        }
        for record in previous.get("accounts", [])
    }
    for account, item_id in saved:
        entries[account["name"]] = {
            "name": account["name"],
            "itemId": item_id,
            "verified": True,
            "verifiedAt": timestamp,
        }
    receipt = {"verifiedAt": timestamp, "accounts": list(entries.values())}
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=path.parent, delete=False
        ) as file:
            temporary = Path(file.name)
            json.dump(receipt, file, indent=2)
        Path(temporary).replace(path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def verify_item(item: dict, account: dict, original: dict | None) -> None:
    """Verify current credentials and retained sensitive login fields.

    Raises:
        RuntimeError: Credentials or preserved fields differ from the intended item.

    """
    login = item.get("login") or {}
    expected_name = updated_item(original, account)["name"]
    if item.get("name") != expected_name:
        raise RuntimeError(f"Bitwarden title verification failed for {account['name']}")
    if not matches_username(item, account):
        raise RuntimeError(
            f"Bitwarden username read-back verification failed for {account['name']}"
        )
    if login.get("password") != account["password"]:
        raise RuntimeError(
            f"Bitwarden password read-back verification failed for {account['name']}"
        )
    expected_uris = updated_item(None, account)["login"]["uris"]
    actual_uris = {
        (uri.get("uri", "").rstrip("/"), uri.get("match"))
        for uri in login.get("uris", [])
    }
    if any(
        (uri["uri"].rstrip("/"), uri["match"]) not in actual_uris
        for uri in expected_uris
    ):
        raise RuntimeError(
            f"Bitwarden autofill URI verification failed for {account['name']}"
        )
    if original:
        for key in ("fido2Credentials", "totp"):
            if login.get(key) != original.get("login", {}).get(key):
                raise RuntimeError(
                    f"Bitwarden preserved login field verification failed for {account['name']}"
                )
        for key in ("notes", "fields", "folderId"):
            if item.get(key) != original.get(key):
                raise RuntimeError(
                    f"Bitwarden preserved item field verification failed for {account['name']}"
                )


def reconcile_status(
    items: list[dict], plan: list[tuple[dict, dict | None]]
) -> tuple[list[tuple[list[dict], dict | None, bool]], list[dict], list[dict]]:
    """Plan changed items and count other domain logins without changing them.

    Returns:
        Account groups, plain unclaimed items, and protected unclaimed items.

    """
    groups = []
    claimed = set()
    for accounts_in_item, original in group_plan(plan):
        updated = original
        for account in accounts_in_item:
            updated = updated_item(updated, account)
        groups.append((accounts_in_item, original, updated != original))
        if original:
            claimed.add(original["id"])

    managed_hosts = {urlsplit(account["url"]).hostname for account, _ in plan} | {
        f"wardrobe.{DOMAIN}",
        f"news.{DOMAIN}",
    }
    extras = []
    unsafe = []
    for item in items:
        if item.get("type") != 1 or item.get("deletedDate") or item["id"] in claimed:
            continue
        login = item.get("login") or {}
        uris = [uri.get("uri", "") for uri in login.get("uris") or []]
        hosts = {urlsplit(uri).hostname for uri in uris}
        domain_hosts = {
            hostname
            for hostname in hosts
            if hostname and (hostname == DOMAIN or hostname.endswith(f".{DOMAIN}"))
        }
        if not domain_hosts:
            continue
        # Keep plain and protected logins in the count. Neither group is changed.
        protected = ("fido2Credentials", "totp")
        item_data = ("attachments", "notes", "fields", "organizationId")
        if (
            hosts - managed_hosts
            or any(login.get(key) for key in protected)
            or any(item.get(key) for key in item_data)
        ):
            unsafe.append(item)
        else:
            extras.append(item)
    return groups, extras, unsafe


def reconcile_vault(
    inventory: list[dict], env: dict, *, apply: bool, only: bool, receipt: Path
) -> None:
    """Plan, optionally apply, and verify vault changes."""
    unlock(env)
    run(["bw", "sync"], env=env)
    existing = json.loads(run(["bw", "list", "items"], env=env))
    # Resolve every match before the first vault mutation.
    plan = build_plan(existing, inventory)
    groups, extras, unsafe = reconcile_status(existing, plan)
    for accounts_in_item, original, changed in groups:
        action = "Create" if original is None else "Update" if changed else "Current"
        print(f"{action}: {', '.join(account['name'] for account in accounts_in_item)}")
    if only:
        # A partial inventory cannot decide whether an unclaimed item is extra.
        extras, unsafe = [], []
    if not apply:
        print(
            f"Plan: {len(inventory)} logins, {len(extras) + len(unsafe)} "
            "other domain logins left untouched; no vault changes."
        )
        return
    apply_plan(plan, groups, env, receipt)


def apply_plan(
    plan: list[tuple[dict, dict | None]],
    groups: list[tuple[list[dict], dict | None, bool]],
    env: dict,
    receipt: Path,
) -> None:
    """Apply a fully checked plan and verify vault readback.

    Raises:
        RuntimeError: An unchanged group has no item to verify.

    """
    saved = []
    for group, item, changed in groups:
        if changed:
            item_id = save_accounts(group, item, env)
        else:
            if item is None:
                message = "An unchanged vault group has no existing item"
                raise RuntimeError(message)
            item_id = item["id"]
        saved.extend((account, item_id) for account in group)
    run(["bw", "sync"], env=env)
    originals = {item["id"]: item for _, item in plan if item}
    for account, item_id in saved:
        item = json.loads(run(["bw", "get", "item", item_id], env=env))
        verify_item(item, account, originals.get(item_id))
        print(f"Verified: {account['name']}")
    write_receipt(receipt, saved)
    print(f"Verified {len(saved)} logins; other vault items were left untouched.")


def main() -> None:
    """Validate, plan, synchronize, and verify the complete login inventory.

    Raises:
        RuntimeError: The operation failed validation or execution.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--credential-via-host", default="macbook-pro-m4")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate complete deployed inventory without accessing the vault",
    )
    parser.add_argument(
        "--only",
        action="append",
        help="Import only this account display name; repeat for multiple accounts",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Write changed logins and verify them without deleting other vault items",
    )
    parser.add_argument(
        "--receipt",
        type=Path,
        default=Path("~/.local/state/homelab-bitwarden/import.json"),
    )
    args = parser.parse_args()
    only = {LEGACY_ACCOUNT_NAMES.get(name, name) for name in args.only or []}
    sources = account_sources()
    if only - sources.keys():
        raise RuntimeError(
            "Unknown account selector; choose one of: " + ", ".join(sources)
        )
    required = sorted({
        source for name in (only or sources.keys()) for source in sources[name]
    })
    inventory = accounts(read_sources(args.credential_via_host, required), only)
    identities = [(account["url"], account["username"]) for account in inventory]
    if len(identities) != len(set(identities)):
        raise RuntimeError(
            "Multiple managed accounts have the same URL and runtime username"
        )
    if args.dry_run:
        for account in inventory:
            print(f"Ready: {account['name']} — {account['url']}")
        print(f"Validated {len(inventory)} deployed logins; no vault changes")
        return
    reconcile_vault(
        inventory,
        os.environ.copy(),
        apply=args.apply,
        only=bool(args.only),
        receipt=args.receipt,
    )


def cli() -> None:
    """Run the command with sanitized failure output."""
    try:
        main()
    except (OSError, RuntimeError, ValueError, KeyError) as error:
        # ValueError can contain decoded input; never expose its message.
        detail = str(error) if isinstance(error, RuntimeError) else type(error).__name__
        print(f"homelab-to-bitwarden: {detail}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    cli()
