"""Complete Aurral setup with sealed Lidarr and listener credentials."""

from __future__ import annotations

import copy
import hashlib
import json
import os
import pathlib
import sys
import urllib.error
import urllib.request
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from collections.abc import Mapping

BASE = os.environ["AURRAL_URL"]
LIDARR = os.environ["LIDARR_URL"]
SLSKD = os.environ["SLSKD_URL"]
STATE = pathlib.Path(os.environ["AURRAL_DATA_DIR"])
DOWNLOADS = pathlib.Path(sys.argv[1])
MUSIC_ROOT = pathlib.Path(sys.argv[2])
CREDENTIALS = pathlib.Path(os.environ["CREDENTIALS_DIRECTORY"])
LIBRARY_METADATA_VERSION = "shared-music-root-v2"
QUALITY_POLICY = json.loads(
    pathlib.Path(os.environ["AURRAL_QUALITY_POLICY"]).read_text(encoding="utf-8")
)
QUALITY_PROFILE_NAME = QUALITY_POLICY["name"]


def request(
    url: str,
    *,
    method: str = "GET",
    payload: object | None = None,
    headers: Mapping[str, str] | None = None,
    timeout: float = 10,
) -> Any:
    """Make one bounded JSON request to the configured service.

    Returns:
        The decoded JSON response, or None for an empty response.

    """
    body = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(
        url,
        data=body,
        method=method,
        headers={"Content-Type": "application/json", **(headers or {})},
    )
    with urllib.request.urlopen(req, timeout=timeout) as response:
        data = response.read()
        return json.loads(data) if data else None


def wait_for_aurral() -> None:
    """Check readiness once, allowing systemd to own any later retry."""
    request(f"{BASE}/api/health/live", timeout=2)


def preferred_profile(api_key: str, endpoint: str) -> int:
    """Select the standard profile or create the intended quality profile.

    Returns:
        The selected profile identifier.

    """
    if endpoint == "qualityprofile":
        return ensure_quality_profile(api_key)
    profiles = request(
        f"{LIDARR}/api/v1/{endpoint}",
        headers={"X-Api-Key": api_key},
    )
    if not isinstance(profiles, list) or not profiles:
        raise RuntimeError(f"Lidarr returned no {endpoint} profiles")
    name = QUALITY_POLICY["onboarding"]["metadataProfileName"]
    for profile in profiles:
        if name.casefold() == str(profile.get("name", "")).casefold():
            return profile["id"]
    raise RuntimeError("Selected Lidarr metadata profile is missing")


def ensure_quality_profile(api_key: str) -> int:
    """Reconcile the selected declarative quality policy.

    Returns:
        The selected or created quality profile identifier.

    """
    url = f"{LIDARR}/api/v1/qualityprofile"
    headers = {"X-Api-Key": api_key}
    profiles = request(url, headers=headers)
    existing = next((p for p in profiles if p["name"] == QUALITY_PROFILE_NAME), None)
    template = existing or next(
        (
            p
            for p in profiles
            if p["name"].casefold() == QUALITY_POLICY["templateName"].casefold()
        ),
        None,
    )
    if not template or not template.get("items"):
        raise RuntimeError("Selected Lidarr quality template is missing")
    profile = copy.deepcopy(existing or template)
    allowed = set(QUALITY_POLICY["allowedQualityNames"])
    cutoff_name = QUALITY_POLICY["cutoffQualityName"]
    cutoff = None

    def select(item: dict[str, Any], cutoff_id: int) -> None:
        nonlocal cutoff
        children = item.get("items", [])
        for child in children:
            select(child, cutoff_id)
        item["allowed"] = (
            any(child["allowed"] for child in children)
            if children
            else item.get("quality", {}).get("name") in allowed
        )

        quality = item.get("quality", {})
        if cutoff_name and cutoff_name == quality.get("name"):
            if not item["allowed"]:
                raise RuntimeError("Selected cutoff quality is not allowed")
            cutoff = cutoff_id

    for item in profile["items"]:
        select(item, item.get("quality", {}).get("id", item.get("id")))
    if cutoff_name and cutoff is None:
        raise RuntimeError("Selected cutoff quality is missing from the template")
    profile.update(
        name=QUALITY_PROFILE_NAME,
        upgradeAllowed=QUALITY_POLICY["upgradeAllowed"],
        cutoff=template["cutoff"] if cutoff is None else cutoff,
    )
    if existing:
        if profile != existing:
            request(
                f"{url}/{existing['id']}",
                method="PUT",
                payload=profile,
                headers=headers,
            )
        return existing["id"]
    profile.pop("id", None)
    return request(url, method="POST", payload=profile, headers=headers)["id"]


def configure_lidarr_quality(
    api_key: str, lidarr_settings: dict[str, Any], auth: Mapping[str, str]
) -> None:
    """Migrate the bootstrap's lossless default, preserving custom selections."""
    marker = STATE / "lidarr-quality-profile-v1"
    previous_id = int(marker.read_text().strip()) if marker.exists() else None
    headers = {"X-Api-Key": api_key}
    profiles = request(f"{LIDARR}/api/v1/qualityprofile", headers=headers)
    old_id = lidarr_settings.get("qualityProfileId")
    old = next((p for p in profiles if p["id"] == old_id), None)
    if previous_id is not None:
        if old_id != previous_id or (old and old["name"] == QUALITY_PROFILE_NAME):
            return
    elif old and old["name"].lower() not in {
        "lossless",
        "flac",
        QUALITY_PROFILE_NAME.lower(),
    }:
        return
    profile_id = ensure_quality_profile(api_key)
    if old_id != profile_id:
        # Complete the artist migration before changing the default, so a retry
        # after an API failure still knows which old profile to migrate.
        artists = request(f"{LIDARR}/api/v1/artist", headers=headers)
        for artist in artists:
            path = pathlib.Path(artist.get("path") or "/")
            if artist.get("qualityProfileId") == old_id and path.is_relative_to(
                MUSIC_ROOT
            ):
                request(
                    f"{LIDARR}/api/v1/artist/{artist['id']}",
                    method="PUT",
                    payload={**artist, "qualityProfileId": profile_id},
                    headers=headers,
                )
        request(
            f"{BASE}/api/settings",
            method="POST",
            payload={"integrations": {"lidarr": {"qualityProfileId": profile_id}}},
            headers=auth,
        )
    marker.write_text(str(profile_id) + "\n")


def configure_import_webhook(api_key: str, auth: Mapping[str, str]) -> None:
    """Notify Aurral immediately after Lidarr imports an album."""
    aurral_key = request(f"{BASE}/api/auth/api-key", headers=auth)["apiKey"]
    headers = {"X-Api-Key": api_key}
    url = f"{LIDARR}/api/v1/notification"
    existing = next(
        (
            item
            for item in request(url, headers=headers)
            if item["name"] == "Aurral imports"
        ),
        None,
    )
    schema = next(
        item
        for item in request(url + "/schema", headers=headers)
        if item["implementation"] == "Webhook"
    )
    desired = copy.deepcopy(existing or schema)
    desired.update(name="Aurral imports", onReleaseImport=True, onUpgrade=True)
    values = {
        "url": f"{BASE}/api/webhooks/lidarr",
        "method": 1,
        "headers": [{"key": "X-Api-Key", "value": aurral_key}],
    }
    for field in desired["fields"]:
        if field["name"] in values:
            field["value"] = values[field["name"]]
    # Validate the actual authenticated service-to-service route before saving.
    request(url + "/test", method="POST", payload=desired, headers=headers)
    if not existing or desired != existing:
        request(
            url + (f"/{existing['id']}" if existing else ""),
            method="PUT" if existing else "POST",
            payload=desired,
            headers=headers,
        )


def retire_navidrome_publishing(auth: Mapping[str, str], settings: dict) -> None:
    """Clear only Aurral's obsolete publishing credentials, preserving Navidrome."""
    fields = ("url", "username", "password")
    saved = settings.get("integrations", {}).get("navidrome", {})
    if any(saved.get(field) for field in fields):
        request(
            f"{BASE}/api/settings",
            method="POST",
            payload={"integrations": {"navidrome": dict.fromkeys(fields, "")}},
            headers=auth,
        )
        confirmed = request(f"{BASE}/api/settings", headers=auth)
        current = confirmed.get("integrations", {}).get("navidrome", {})
        if any(current.get(field) for field in fields):
            raise RuntimeError(
                "Aurral Navidrome publishing credentials were not cleared"
            )
    (STATE / "navidrome-profile").unlink(missing_ok=True)


def lidarr_music_root(api_key: str) -> str:
    """Check that Lidarr has the configured music library root.

    Returns:
        The configured music root path.

    """
    folders = request(
        f"{LIDARR}/api/v1/rootfolder",
        headers={"X-Api-Key": api_key},
        timeout=2,
    )
    if not isinstance(folders, list) or not any(
        isinstance(folder, dict)
        and folder.get("path")
        and pathlib.Path(folder["path"]) == MUSIC_ROOT
        for folder in folders
    ):
        raise RuntimeError("Lidarr does not have the configured music root")
    return str(MUSIC_ROOT)


def admin_password() -> str:
    """Read the administrator password from the service credential directory.

    Returns:
        The sealed administrator password.

    """
    return (CREDENTIALS / "aurral-admin-password").read_text().strip()


def admin_username() -> str:
    """Read the administrator username from the service credential directory.

    Returns:
        The sealed administrator username.

    """
    return (CREDENTIALS / "aurral-admin-username").read_text().strip()


def slskd_api_key() -> str:
    """Read the API key from the service's generated slskd settings.

    Returns:
        The slskd API key.

    """
    lines = (CREDENTIALS / "slskd-settings").read_text().splitlines()
    for line in lines:
        name, separator, value = line.partition("=")
        if separator and name.strip() == "SLSKD_API_KEY":
            key = value.strip().strip("\"'")
            if key:
                return key
    raise RuntimeError("slskd API key is missing from its sealed settings")


def configure_lidarr_connection(
    api_key: str, music_root: str, current: dict, auth: Mapping[str, str]
) -> dict:
    """Apply vanilla Aurral's authenticated integration contract after onboarding.

    Returns:
        Existing options merged with the confirmed connection settings.

    """
    roots = current.get("rootFolderPaths") or []
    desired = {
        "url": LIDARR,
        "apiKey": api_key,
        "enabled": True,
        "rootFolderPaths": [
            music_root,
            *(root for root in roots if root != music_root),
        ],
        "qualityProfileId": current.get("qualityProfileId")
        or preferred_profile(api_key, "qualityprofile"),
        "metadataProfileId": current.get("metadataProfileId")
        or preferred_profile(api_key, "metadataprofile"),
        "defaultMonitorOption": current.get(
            "defaultMonitorOption", QUALITY_POLICY["onboarding"]["defaultMonitorOption"]
        ),
        "searchOnAdd": current.get(
            "searchOnAdd", QUALITY_POLICY["onboarding"]["searchOnAdd"]
        ),
    }
    if any(current.get(key) != value for key, value in desired.items()):
        request(
            f"{BASE}/api/settings",
            method="POST",
            payload={"integrations": {"lidarr": desired}},
            headers=auth,
        )
        confirmed = request(f"{BASE}/api/settings", headers=auth)
        selected = confirmed.get("integrations", {}).get("lidarr", {})
        # Secret fields may be redacted by the server; confirm every public field.
        if any(
            selected.get(key) != value
            for key, value in desired.items()
            if key != "apiKey"
        ):
            raise RuntimeError("Aurral Lidarr integration settings were not confirmed")
    return {**current, **desired}


def configure_listening_history(username: str, auth: Mapping[str, str]) -> None:
    """Save only this history provider and verify the server acknowledgement."""
    history = request(
        f"{BASE}/api/users/me/listening-history",
        method="PATCH",
        payload={"listenbrainz": username},
        headers=auth,
    )
    if not isinstance(history, dict) or history.get("listenbrainz") != username:
        raise RuntimeError("ListenBrainz history account was not confirmed")
    (STATE / "listenbrainz-profile").write_text(username + "\n")


def configure_listenbrainz_scrobbling(
    identity: dict[str, Any], auth: Mapping[str, str]
) -> None:
    """Apply the configured account to the scrobbling integration."""
    token = str(identity.get("token") or "").strip()
    username = str(identity.get("listenbrainzUsername") or "").strip()
    if not token or not username:
        return
    marker = STATE / "listenbrainz-scrobbling-profile"
    identity_bytes = (username + "\0" + token).encode()
    fingerprint = hashlib.sha256(identity_bytes).hexdigest()
    receipt_path = os.environ.get("LISTENBRAINZ_IDENTITY_RECEIPT")
    if not receipt_path:
        raise RuntimeError("ListenBrainz verification receipt is missing")
    receipt = json.loads(pathlib.Path(receipt_path).read_text(encoding="utf-8"))
    if receipt.get("username") != username or receipt.get("fingerprint") != fingerprint:
        raise RuntimeError(
            "ListenBrainz verification receipt does not match the configured identity"
        )
    connections = request(f"{BASE}/api/scrobbling/status", headers=auth)
    status = connections.get("listenbrainz", {})
    if (
        marker.exists()
        and marker.read_text().strip() == fingerprint
        and status.get("connected")
        and status.get("displayName") == username
    ):
        return
    linked = request(
        f"{BASE}/api/scrobbling/listenbrainz/link",
        method="PUT",
        payload={"token": token},
        headers=auth,
    )
    if not linked.get("connected") or linked.get("displayName") != username:
        raise RuntimeError("ListenBrainz account verification failed")
    marker.write_text(fingerprint + "\n")


def main() -> None:
    """Configure the selected music integrations after application readiness."""
    api_key = (CREDENTIALS / "lidarr-api-key").read_text().strip()
    if not api_key:
        raise RuntimeError("Lidarr API key is empty")
    if os.environ.get("AURRAL_QUALITY_ONLY") == "1":
        ensure_quality_profile(api_key)
        print("Lidarr music quality profile is ready")
        return
    wait_for_aurral()
    music_root = lidarr_music_root(api_key)
    bootstrap = request(f"{BASE}/api/health/bootstrap")
    onboarding_required = bootstrap.get("onboardingRequired", False)
    metadata_marker = STATE / "library-metadata-version"
    refresh_library = (
        onboarding_required
        or not metadata_marker.exists()
        or metadata_marker.read_text().strip() != LIBRARY_METADATA_VERSION
    )
    if onboarding_required:
        request(
            f"{BASE}/api/onboarding/complete",
            method="POST",
            payload={
                "authUser": admin_username(),
                "authPassword": admin_password(),
                "security": {
                    "localNetworkBypass": {
                        "enabled": QUALITY_POLICY["onboarding"]["localNetworkBypass"]
                    }
                },
                "downloadFolderPath": str(DOWNLOADS),
            },
        )
    identity = json.loads((CREDENTIALS / "listenbrainz-identity").read_text())
    listenbrainz_user = str(identity.get("listenbrainzUsername") or "").strip()
    history_marker = STATE / "listenbrainz-profile"
    configure_history = (
        listenbrainz_user
        and (CREDENTIALS / "aurral-admin-password").exists()
        and (
            not history_marker.exists()
            or history_marker.read_text().strip() != listenbrainz_user
        )
    )
    slskd_key = slskd_api_key()
    slskd_identity_bytes = (SLSKD + "\0" + slskd_key).encode()
    slskd_fingerprint = hashlib.sha256(slskd_identity_bytes).hexdigest()
    slskd_marker = STATE / "slskd-profile"
    configure_slskd = (CREDENTIALS / "aurral-admin-password").exists() and (
        not slskd_marker.exists()
        or slskd_marker.read_text().strip() != slskd_fingerprint
    )
    has_admin_password = (CREDENTIALS / "aurral-admin-password").exists()
    if configure_history or configure_slskd or has_admin_password:
        login = request(
            f"{BASE}/api/auth/login",
            method="POST",
            payload={"username": admin_username(), "password": admin_password()},
        )
        auth = {"Authorization": f"Bearer {login['token']}"}
        settings = request(f"{BASE}/api/settings", headers=auth)
        if os.environ.get("AURRAL_LIDARR_WEBHOOK") == "1":
            configure_import_webhook(api_key, auth)
        retire_navidrome_publishing(auth, settings)
        if settings.get("downloadFolderPath") != str(DOWNLOADS):
            request(
                f"{BASE}/api/settings",
                method="POST",
                payload={"downloadFolderPath": str(DOWNLOADS)},
                headers=auth,
            )
            refresh_library = True
        integrations = settings.get("integrations", {})
        previous_lidarr = integrations.get("lidarr", {})
        lidarr_settings = configure_lidarr_connection(
            api_key, music_root, previous_lidarr, auth
        )
        configure_lidarr_quality(api_key, lidarr_settings, auth)
        if previous_lidarr.get("rootFolderPaths") != lidarr_settings.get(
            "rootFolderPaths"
        ):
            refresh_library = True
        if configure_history:
            configure_listening_history(listenbrainz_user, auth)
        configure_listenbrainz_scrobbling(identity, auth)
        if configure_slskd:
            saved_slskd = integrations.get("slskd", {})
            initial_settings = (
                {"enabled": True, **QUALITY_POLICY["slskd"]}
                if not slskd_marker.exists() and not saved_slskd.get("url")
                else saved_slskd
            )
            request(
                f"{BASE}/api/settings",
                method="POST",
                payload={
                    "integrations": {
                        "slskd": {
                            **initial_settings,
                            "url": SLSKD,
                            "apiKey": slskd_key,
                        }
                    }
                },
                headers=auth,
            )
            slskd_marker.write_text(slskd_fingerprint + "\n")
        if refresh_library:
            refreshed = request(
                f"{BASE}/api/library/refresh",
                method="POST",
                payload={"mode": "full"},
                headers=auth,
            )
            if not isinstance(refreshed, dict) or refreshed.get("queued") is not True:
                raise RuntimeError("Aurral library refresh was not queued")
            metadata_marker.write_text(LIBRARY_METADATA_VERSION + "\n")
    print("Aurral onboarding and music integrations are ready")


if __name__ == "__main__":
    try:
        main()
    except (
        OSError,
        ValueError,
        KeyError,
        RuntimeError,
        urllib.error.HTTPError,
    ) as error:
        # The request bodies include credentials. Never print them on failure.
        print(
            f"Aurral bootstrap failed: {type(error).__name__}",
            file=sys.stderr,
        )
        sys.exit(1)
