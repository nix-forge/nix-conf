from __future__ import annotations

import json
import os
import pathlib
import urllib.parse
from collections.abc import Iterable
from datetime import UTC, datetime
from typing import Any

from lib.api import ApiClient
from lib.wait import wait_for

ARR_API_KEY_ENVS = (
    "PROWLARR_API_KEY",
    "SONARR_API_KEY",
    "RADARR_API_KEY",
    "LIDARR_API_KEY",
    "READARR_API_KEY",
)

JELLYFIN_BOOTSTRAP_APP_NAME = "homelab-reconcile"


def copy_env_if_present(target_env: str, source_env: str) -> None:
    if value_present(maybe_env(target_env)):
        return
    source_value = maybe_env(source_env)
    if not value_present(source_value):
        return
    if source_value is None:
        return
    os.environ[target_env] = source_value


def value_present(value: str | None) -> bool:
    if value is None:
        return False
    trimmed = value.strip()
    return trimmed != "" and trimmed != "bootstrap-change-me"


def maybe_configure_servarr_env_api_keys() -> None:
    copy_env_if_present("PROWLARR_API_KEY", "PROWLARR__AUTH__APIKEY")
    copy_env_if_present("SONARR_API_KEY", "SONARR__AUTH__APIKEY")
    copy_env_if_present("RADARR_API_KEY", "RADARR__AUTH__APIKEY")
    copy_env_if_present("LIDARR_API_KEY", "LIDARR__AUTH__APIKEY")
    copy_env_if_present("READARR_API_KEY", "READARR__AUTH__APIKEY")
    copy_env_if_present("SEERR_API_KEY", "API_KEY")
    copy_env_if_present("API_KEY", "SEERR_API_KEY")


def ensure_required_env_vars(names: Iterable[str]) -> None:
    missing = [name for name in names if not value_present(maybe_env(name))]
    if missing:
        raise RuntimeError(
            f"missing required integration environment variables: {', '.join(missing)}"
        )


def maybe_raise_api_key_bootstrap_error() -> None:
    keys = [name for name in ARR_API_KEY_ENVS if value_present(maybe_env(name))]
    if keys:
        return
    raise RuntimeError("missing API keys for Arr/Prowlarr/Seerr bootstrap")


def ensure_seerr_api_key() -> None:
    if value_present(maybe_env("SEERR_API_KEY")):
        copy_env_if_present("API_KEY", "SEERR_API_KEY")
        return
    if value_present(maybe_env("API_KEY")):
        copy_env_if_present("SEERR_API_KEY", "API_KEY")
        return
    raise RuntimeError(
        "missing SEERR_API_KEY bootstrap; set SEERR_API_KEY or API_KEY in "
        "homelab-reconcile-env"
    )


def ensure_jellyfin_admin_username(values: dict[str, Any]) -> str:
    explicit = maybe_env("JELLYFIN_ADMIN_USERNAME")
    if value_present(explicit):
        assert explicit is not None
        return explicit

    client = ApiClient(base_url=values["jellyfin"]["url"], default_headers={})
    wait_for(
        lambda: client.request("GET", "/Users/Public", expected={200}) is not None,
        name="jellyfin public users",
    )
    _, users = client.request("GET", "/Users/Public", expected={200})
    users_list = users if isinstance(users, list) else []

    for preferred in ("admin", "jellyfin", "MyJellyfinUser"):
        for user in users_list:
            if not isinstance(user, dict):
                continue
            name = user.get("Name")
            if isinstance(name, str) and name.strip() == preferred:
                os.environ["JELLYFIN_ADMIN_USERNAME"] = preferred
                return preferred

    candidates: list[str] = []
    for user in users_list:
        if not isinstance(user, dict):
            continue
        name = user.get("Name")
        if isinstance(name, str) and name.strip():
            candidates.append(name.strip())

    if len(candidates) == 1:
        os.environ["JELLYFIN_ADMIN_USERNAME"] = candidates[0]
        return candidates[0]

    raise RuntimeError(
        "unable to determine jellyfin admin username from /Users/Public; set "
        "JELLYFIN_ADMIN_USERNAME in homelab-reconcile-env"
    )


def maybe_complete_jellyfin_startup(
    values: dict[str, Any],
    *,
    admin_user: str,
    admin_password: str,
) -> None:
    client = ApiClient(base_url=values["jellyfin"]["url"], default_headers={})
    _, public_info = client.request("GET", "/System/Info/Public", expected={200})
    if not isinstance(public_info, dict):
        return
    startup_done = public_info.get("StartupWizardCompleted")
    if startup_done is not False:
        return

    client.request(
        "POST",
        "/Startup/User",
        expected={204},
        json_body={
            "Name": admin_user,
            "Password": admin_password,
        },
    )
    client.request(
        "POST",
        "/Startup/Configuration",
        expected={204},
        json_body={},
    )
    client.request(
        "POST",
        "/Startup/RemoteAccess",
        expected={204},
        json_body={
            "EnableRemoteAccess": False,
            "EnableAutomaticPortMapping": False,
        },
    )
    client.request("POST", "/Startup/Complete", expected={204})


def ensure_jellyfin_token(values: dict[str, Any], *, required: bool) -> str | None:
    token = maybe_env("JELLYFIN_API_TOKEN")
    if value_present(token):
        assert token is not None
        return token

    admin_password = maybe_env("JELLYFIN_ADMIN_PASSWORD")
    if not value_present(admin_password):
        if required:
            raise RuntimeError(
                "missing jellyfin credentials for token bootstrap; set "
                "JELLYFIN_API_TOKEN or JELLYFIN_ADMIN_PASSWORD in "
                "homelab-reconcile-env"
            )
        return None
    assert admin_password is not None
    try:
        admin_user = ensure_jellyfin_admin_username(values)

        maybe_complete_jellyfin_startup(
            values,
            admin_user=admin_user,
            admin_password=admin_password,
        )

        client = ApiClient(base_url=values["jellyfin"]["url"], default_headers={})

        wait_for(
            lambda: (
                client.request("GET", "/System/Info/Public", expected={200}) is not None
            ),
            name="jellyfin public api",
        )

        _, auth = client.request(
            "POST",
            "/Users/AuthenticateByName",
            expected={200},
            headers={
                "Authorization": (
                    'MediaBrowser Client="homelab-reconcile", '
                    'Device="homelab-reconcile", '
                    'DeviceId="homelab-reconcile", Version="1.0"'
                )
            },
            json_body={
                "Username": admin_user,
                "Pw": admin_password,
            },
        )

        if not isinstance(auth, dict):
            raise RuntimeError("jellyfin auth response was not an object")

        access_token = auth.get("AccessToken")
        if not isinstance(access_token, str) or not access_token.strip():
            raise RuntimeError("jellyfin auth response missing AccessToken")

        media_headers = {
            "Authorization": (
                'MediaBrowser Client="homelab-reconcile", '
                'Device="homelab-reconcile", '
                'DeviceId="homelab-reconcile", Version="1.0", '
                f'Token="{access_token.strip()}"'
            )
        }
        media_client = ApiClient(
            base_url=values["jellyfin"]["url"],
            default_headers=media_headers,
        )

        token_endpoint = "/Auth/Keys"

        _, keys_payload = media_client.request("GET", token_endpoint, expected={200})
        keys_list = []
        if isinstance(keys_payload, dict):
            items = keys_payload.get("Items")
            if isinstance(items, list):
                keys_list = items
        elif isinstance(keys_payload, list):
            keys_list = keys_payload

        for item in reversed(keys_list):
            if not isinstance(item, dict):
                continue
            if item.get("AppName") != JELLYFIN_BOOTSTRAP_APP_NAME:
                continue
            key = item.get("AccessToken")
            if isinstance(key, str) and key.strip():
                os.environ["JELLYFIN_API_TOKEN"] = key.strip()
                return key.strip()

        token_query = urllib.parse.urlencode({"App": JELLYFIN_BOOTSTRAP_APP_NAME})
        media_client.request(
            "POST",
            f"{token_endpoint}?{token_query}",
            expected={200, 204},
        )
        _, keys_payload = media_client.request("GET", token_endpoint, expected={200})
        keys_list = []
        if isinstance(keys_payload, dict):
            items = keys_payload.get("Items")
            if isinstance(items, list):
                keys_list = items
        elif isinstance(keys_payload, list):
            keys_list = keys_payload

        for item in reversed(keys_list):
            if not isinstance(item, dict):
                continue
            if item.get("AppName") != JELLYFIN_BOOTSTRAP_APP_NAME:
                continue
            key = item.get("AccessToken")
            if isinstance(key, str) and key.strip():
                os.environ["JELLYFIN_API_TOKEN"] = key.strip()
                return key.strip()

        raise RuntimeError("failed to discover jellyfin api token after bootstrap")
    except RuntimeError:
        if required:
            raise
        return None


def env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"missing required environment variable: {name}")
    return value


def maybe_env(name: str) -> str | None:
    value = os.environ.get(name, "").strip()
    return value or None


def env_from_optional(spec: dict[str, Any], key: str) -> str | None:
    name = spec.get(key)
    if not isinstance(name, str) or not name.strip():
        return None
    return env(name)


def find_field(fields: list[dict[str, Any]], *names: str) -> dict[str, Any] | None:
    for field in fields:
        field_name = field.get("name")
        if isinstance(field_name, str) and field_name in names:
            return field
    return None


def set_field_required(
    fields: list[dict[str, Any]],
    value: Any,
    *,
    aliases: tuple[str, ...],
    context: str,
) -> None:
    field = find_field(fields, *aliases)
    if field is None:
        raise RuntimeError(
            f"{context}: required field missing; expected one of {aliases}"
        )
    field["value"] = value


def set_field_if_present(
    fields: list[dict[str, Any]],
    value: Any,
    *,
    aliases: tuple[str, ...],
) -> bool:
    field = find_field(fields, *aliases)
    if field is None:
        return False
    field["value"] = value
    return True


def schema_by_name(items: list[dict[str, Any]], key: str, value: str) -> dict[str, Any]:
    for item in items:
        if item.get(key) == value:
            return item

    wanted = value.casefold()
    for item in items:
        candidate = item.get(key)
        if isinstance(candidate, str) and candidate.casefold() == wanted:
            return item

    raise RuntimeError(f"schema missing {key}={value}")


def upsert_named(
    client: ApiClient,
    *,
    list_path: str,
    create_path: str,
    update_path_prefix: str,
    name: str,
    payload: dict[str, Any],
) -> str:
    _, existing = client.request("GET", list_path, expected={200})
    existing_items = existing if isinstance(existing, list) else []

    existing_item = next((i for i in existing_items if i.get("name") == name), None)
    if existing_item is None:
        _, body = client.request(
            "POST", create_path, expected={200, 201}, json_body=payload
        )
        if isinstance(body, dict) and isinstance(body.get("id"), int):
            return str(body["id"])
        return "created"

    item_id = existing_item.get("id")
    if item_id is None:
        raise RuntimeError(f"existing object missing id: {name}")

    payload["id"] = item_id
    client.request(
        "PUT",
        f"{update_path_prefix}/{item_id}",
        expected={200, 202},
        json_body=payload,
    )
    return str(item_id)


def prune_named(
    client: ApiClient,
    *,
    list_path: str,
    delete_path_prefix: str,
    keep_names: set[str],
    id_key: str = "id",
) -> list[str]:
    _, existing = client.request("GET", list_path, expected={200})
    existing_items = existing if isinstance(existing, list) else []
    deleted: list[str] = []
    for item in existing_items:
        name = item.get("name")
        if not isinstance(name, str) or name in keep_names:
            continue
        item_id = item.get(id_key)
        if item_id is None:
            continue
        client.request("DELETE", f"{delete_path_prefix}/{item_id}", expected={200, 202})
        deleted.append(name)
    return deleted


def reconcile_prowlarr(values: dict[str, Any], state: dict[str, Any]) -> None:
    client = ApiClient(
        base_url=values["prowlarr"]["url"],
        default_headers={"X-Api-Key": env("PROWLARR_API_KEY")},
    )

    wait_for(
        lambda: (
            client.request("GET", "/api/v1/system/status", expected={200}) is not None
        ),
        name="prowlarr api",
    )

    phase = state.setdefault("prowlarr", {})

    wait_for(
        lambda: (
            client.request("GET", "/api/v1/applications/schema", expected={200})
            is not None
        ),
        name="prowlarr application schema",
    )
    _, app_schemas = client.request(
        "GET", "/api/v1/applications/schema", expected={200}
    )
    app_schemas_list = app_schemas if isinstance(app_schemas, list) else []

    managed_apps: set[str] = set()
    for app in values["prowlarr"]["applications"]:
        arr_cfg = values["arr"][app["service"]]
        arr_client = ApiClient(
            base_url=arr_cfg["url"],
            default_headers={"X-Api-Key": env(f"{app['service'].upper()}_API_KEY")},
        )
        wait_for(
            lambda: (
                arr_client.request(
                    "GET",
                    f"/api/{arr_cfg['apiVersion']}/system/status",
                    expected={200},
                )
                is not None
            ),
            name=f"{app['service']} api for prowlarr",
        )

        schema = schema_by_name(
            app_schemas_list, "implementationName", app["implementationName"]
        )
        payload = dict(schema)
        payload["name"] = app["name"]

        fields = payload.get("fields", [])
        if not isinstance(fields, list):
            raise RuntimeError(f"prowlarr app schema fields invalid for {app['name']}")
        set_field_required(
            fields,
            values["arr"][app["service"]]["url"],
            aliases=("baseUrl",),
            context=f"prowlarr application {app['name']}",
        )
        set_field_required(
            fields,
            env(f"{app['service'].upper()}_API_KEY"),
            aliases=("apiKey",),
            context=f"prowlarr application {app['name']}",
        )
        set_field_if_present(
            fields, values["prowlarr"]["url"], aliases=("prowlarrUrl",)
        )

        upsert_named(
            client,
            list_path="/api/v1/applications",
            create_path="/api/v1/applications",
            update_path_prefix="/api/v1/applications",
            name=app["name"],
            payload=payload,
        )
        managed_apps.add(app["name"])

    if values["prowlarr"]["prune"]["applications"]:
        phase["prunedApplications"] = prune_named(
            client,
            list_path="/api/v1/applications",
            delete_path_prefix="/api/v1/applications",
            keep_names=managed_apps,
        )

    wait_for(
        lambda: (
            client.request("GET", "/api/v1/downloadclient/schema", expected={200})
            is not None
        ),
        name="prowlarr download client schema",
    )
    _, dc_schemas = client.request(
        "GET", "/api/v1/downloadclient/schema", expected={200}
    )
    dc_schemas_list = dc_schemas if isinstance(dc_schemas, list) else []

    managed_downloaders: set[str] = set()
    for key, dc in values["downloadClients"].items():
        schema = schema_by_name(
            dc_schemas_list, "implementationName", dc["implementation"]
        )
        payload = dict(schema)
        payload["name"] = dc["name"]
        payload["enable"] = True

        fields = payload.get("fields", [])
        if not isinstance(fields, list):
            raise RuntimeError(
                f"prowlarr downloader schema fields invalid for {dc['name']}"
            )
        set_field_required(
            fields,
            dc["host"],
            aliases=("host",),
            context=f"prowlarr downloader {dc['name']}",
        )
        set_field_required(
            fields,
            dc["port"],
            aliases=("port",),
            context=f"prowlarr downloader {dc['name']}",
        )
        set_field_if_present(fields, dc["urlBase"], aliases=("urlBase",))
        set_field_if_present(fields, dc["useSsl"], aliases=("useSsl", "ssl"))
        set_field_if_present(fields, dc.get("category"), aliases=("category",))

        if key == "qbittorrent":
            set_field_required(
                fields,
                env("QBITTORRENT_USERNAME"),
                aliases=("username",),
                context="prowlarr downloader qBittorrent",
            )
            set_field_required(
                fields,
                env("QBITTORRENT_PASSWORD"),
                aliases=("password",),
                context="prowlarr downloader qBittorrent",
            )
        if key == "nzbget":
            set_field_required(
                fields,
                env("NZBGET_USERNAME"),
                aliases=("username",),
                context="prowlarr downloader NZBGet",
            )
            set_field_required(
                fields,
                env("NZBGET_PASSWORD"),
                aliases=("password",),
                context="prowlarr downloader NZBGet",
            )

        upsert_named(
            client,
            list_path="/api/v1/downloadclient",
            create_path="/api/v1/downloadclient",
            update_path_prefix="/api/v1/downloadclient",
            name=dc["name"],
            payload=payload,
        )
        managed_downloaders.add(dc["name"])

    if values["prowlarr"]["prune"]["downloadClients"]:
        phase["prunedDownloadClients"] = prune_named(
            client,
            list_path="/api/v1/downloadclient",
            delete_path_prefix="/api/v1/downloadclient",
            keep_names=managed_downloaders,
        )

    wait_for(
        lambda: (
            client.request("GET", "/api/v1/indexer/schema", expected={200}) is not None
        ),
        name="prowlarr indexer schema",
    )
    _, indexer_schemas = client.request("GET", "/api/v1/indexer/schema", expected={200})
    indexer_schemas_list = indexer_schemas if isinstance(indexer_schemas, list) else []

    managed_indexers: set[str] = set()
    for indexer in values["prowlarr"].get("indexers", []):
        schema = schema_by_name(
            indexer_schemas_list, "implementationName", indexer["implementationName"]
        )
        payload = dict(schema)
        payload["name"] = indexer["name"]
        payload["enable"] = indexer.get("enable", True)
        payload["enableRss"] = indexer.get("enableRss", True)
        payload["enableAutomaticSearch"] = indexer.get("enableAutomaticSearch", True)
        payload["priority"] = indexer.get("priority", 25)

        fields = payload.get("fields", [])
        if not isinstance(fields, list):
            raise RuntimeError(
                f"prowlarr indexer schema fields invalid for {indexer['name']}"
            )

        api_key_value = env_from_optional(indexer, "apiKeyEnv")
        if api_key_value is not None:
            set_field_required(
                fields,
                api_key_value,
                aliases=("apiKey",),
                context=f"prowlarr indexer {indexer['name']}",
            )

        username_value = env_from_optional(indexer, "usernameEnv")
        if username_value is not None:
            set_field_required(
                fields,
                username_value,
                aliases=("username",),
                context=f"prowlarr indexer {indexer['name']}",
            )

        password_value = env_from_optional(indexer, "passwordEnv")
        if password_value is not None:
            set_field_required(
                fields,
                password_value,
                aliases=("password",),
                context=f"prowlarr indexer {indexer['name']}",
            )

        for raw_field, raw_value in indexer.get("fields", {}).items():
            if not isinstance(raw_field, str):
                continue
            set_field_required(
                fields,
                raw_value,
                aliases=(raw_field,),
                context=f"prowlarr indexer {indexer['name']}",
            )

        upsert_named(
            client,
            list_path="/api/v1/indexer",
            create_path="/api/v1/indexer",
            update_path_prefix="/api/v1/indexer",
            name=indexer["name"],
            payload=payload,
        )
        managed_indexers.add(indexer["name"])

    if values["prowlarr"]["prune"]["indexers"]:
        phase["prunedIndexers"] = prune_named(
            client,
            list_path="/api/v1/indexer",
            delete_path_prefix="/api/v1/indexer",
            keep_names=managed_indexers,
        )


def apply_media_management(
    arr_name: str, client: ApiClient, arr: dict[str, Any]
) -> None:
    settings = arr.get("mediaManagement")
    if not isinstance(settings, dict) or settings == {}:
        return

    base = f"/api/{arr['apiVersion']}"
    _, current = client.request("GET", f"{base}/config/mediamanagement", expected={200})
    if not isinstance(current, dict):
        raise RuntimeError(f"{arr_name}: invalid media management response")

    merged = dict(current)
    for key, value in settings.items():
        merged[key] = value

    client.request(
        "PUT", f"{base}/config/mediamanagement", expected={202}, json_body=merged
    )


def ensure_root_folders(
    arr_name: str, client: ApiClient, arr: dict[str, Any], state: dict[str, Any]
) -> None:
    base = f"/api/{arr['apiVersion']}"
    _, root_folders = client.request("GET", f"{base}/rootfolder", expected={200})
    current_paths = {
        item.get("path")
        for item in root_folders
        if isinstance(item, dict) and isinstance(item.get("path"), str)
    }

    created: list[str] = []
    for path in arr.get("rootFolders", []):
        if path in current_paths:
            continue

        payload: dict[str, Any] = {"path": path}
        if arr_name in {"lidarr", "readarr"}:
            payload["name"] = pathlib.Path(path).name or arr_name.capitalize()

            _, quality_profiles = client.request(
                "GET", f"{base}/qualityprofile", expected={200}
            )
            if isinstance(quality_profiles, list) and quality_profiles:
                first = quality_profiles[0]
                if isinstance(first, dict) and isinstance(first.get("id"), int):
                    payload["defaultQualityProfileId"] = first["id"]

            _, metadata_profiles = client.request(
                "GET", f"{base}/metadataprofile", expected={200}
            )
            if isinstance(metadata_profiles, list) and metadata_profiles:
                first = metadata_profiles[0]
                if isinstance(first, dict) and isinstance(first.get("id"), int):
                    payload["defaultMetadataProfileId"] = first["id"]

        client.request("POST", f"{base}/rootfolder", expected={201}, json_body=payload)
        created.append(path)

    if created:
        state.setdefault("arrRootFoldersCreated", {})[arr_name] = created


def pick_download_client_category(arr_name: str) -> str:
    if arr_name == "sonarr":
        return "Series"
    if arr_name == "radarr":
        return "Movies"
    if arr_name == "lidarr":
        return "Music"
    if arr_name == "readarr":
        return "Books"
    return "Prowlarr"


def reconcile_arr(values: dict[str, Any], state: dict[str, Any]) -> None:
    for arr_name, arr in values["arr"].items():
        client = ApiClient(
            base_url=arr["url"],
            default_headers={"X-Api-Key": env(f"{arr_name.upper()}_API_KEY")},
        )

        wait_for(
            lambda: (
                client.request(
                    "GET", f"/api/{arr['apiVersion']}/system/status", expected={200}
                )
                is not None
            ),
            name=f"{arr_name} api",
        )

        ensure_root_folders(arr_name, client, arr, state)
        apply_media_management(arr_name, client, arr)

        base = f"/api/{arr['apiVersion']}/downloadclient"
        _, schemas = client.request("GET", f"{base}/schema", expected={200})
        schemas_list = schemas if isinstance(schemas, list) else []

        managed_downloaders: set[str] = set()
        for key, dc in values["downloadClients"].items():
            schema = schema_by_name(
                schemas_list, "implementationName", dc["implementation"]
            )
            payload = dict(schema)
            payload["name"] = dc["name"]
            payload["enable"] = True

            fields = payload.get("fields", [])
            if not isinstance(fields, list):
                raise RuntimeError(
                    f"{arr_name}: invalid downloader schema for {dc['name']}"
                )

            set_field_required(
                fields,
                dc["host"],
                aliases=("host",),
                context=f"{arr_name} downloader {dc['name']}",
            )
            set_field_required(
                fields,
                dc["port"],
                aliases=("port",),
                context=f"{arr_name} downloader {dc['name']}",
            )

            category_set = set_field_if_present(
                fields, arr["category"], aliases=("category",)
            )
            if not category_set:
                set_field_if_present(
                    fields,
                    arr["category"],
                    aliases=(
                        "tvCategory",
                        "movieCategory",
                        "musicCategory",
                        "bookCategory",
                    ),
                )
            set_field_if_present(
                fields,
                pick_download_client_category(arr_name),
                aliases=(
                    "tvCategory",
                    "movieCategory",
                    "musicCategory",
                    "bookCategory",
                ),
            )

            set_field_if_present(fields, dc["urlBase"], aliases=("urlBase",))
            set_field_if_present(fields, dc["useSsl"], aliases=("useSsl", "ssl"))
            set_field_if_present(fields, dc.get("category"), aliases=("category",))

            if key == "qbittorrent":
                set_field_required(
                    fields,
                    env("QBITTORRENT_USERNAME"),
                    aliases=("username",),
                    context=f"{arr_name} downloader qBittorrent",
                )
                set_field_required(
                    fields,
                    env("QBITTORRENT_PASSWORD"),
                    aliases=("password",),
                    context=f"{arr_name} downloader qBittorrent",
                )

            if key == "nzbget":
                set_field_required(
                    fields,
                    env("NZBGET_USERNAME"),
                    aliases=("username",),
                    context=f"{arr_name} downloader NZBGet",
                )
                set_field_required(
                    fields,
                    env("NZBGET_PASSWORD"),
                    aliases=("password",),
                    context=f"{arr_name} downloader NZBGet",
                )

            upsert_named(
                client,
                list_path=base,
                create_path=base,
                update_path_prefix=base,
                name=dc["name"],
                payload=payload,
            )
            managed_downloaders.add(dc["name"])

        if values["prowlarr"]["prune"]["downloadClients"]:
            prune_named(
                client,
                list_path=base,
                delete_path_prefix=base,
                keep_names=managed_downloaders,
            )


def pick_profile_id(resp: dict[str, Any]) -> int:
    profiles = resp.get("profiles", [])
    if not profiles:
        raise RuntimeError("seerr test response did not include profiles")
    profile_id = profiles[0].get("id")
    if not isinstance(profile_id, int):
        raise RuntimeError("seerr profile id missing")
    return profile_id


def maybe_bootstrap_seerr(values: dict[str, Any]) -> None:
    public_client = ApiClient(
        base_url=values["seerr"]["url"],
        default_headers={},
    )

    _, public_settings = public_client.request(
        "GET", "/api/v1/settings/public", expected={200}
    )
    if not isinstance(public_settings, dict):
        return

    if public_settings.get("initialized") is not False:
        return

    admin_password = maybe_env("SEERR_JELLYFIN_ADMIN_PASSWORD") or maybe_env(
        "JELLYFIN_ADMIN_PASSWORD"
    )
    if not value_present(admin_password):
        raise RuntimeError(
            "seerr initialization required but missing Jellyfin admin password; set "
            "SEERR_JELLYFIN_ADMIN_PASSWORD or JELLYFIN_ADMIN_PASSWORD in "
            "homelab-reconcile-env"
        )
    assert admin_password is not None

    admin_username = maybe_env("SEERR_JELLYFIN_ADMIN_USERNAME")
    if not value_present(admin_username):
        admin_username = ensure_jellyfin_admin_username(values)
    assert admin_username is not None

    jellyfin = values["seerr"]["jellyfin"]
    setup_payload: dict[str, Any] = {
        "username": admin_username,
        "password": admin_password,
        "email": maybe_env("SEERR_ADMIN_EMAIL") or f"{admin_username}@local",
        "hostname": jellyfin["ip"],
        "port": jellyfin["port"],
        "urlBase": jellyfin["urlBase"],
        "useSsl": jellyfin["useSsl"],
        "serverType": 2,
    }

    try:
        public_client.request(
            "POST", "/api/v1/auth/jellyfin", expected={200}, json_body=setup_payload
        )
    except RuntimeError as exc:
        if "Jellyfin hostname already configured" not in str(exc):
            raise
        retry_payload = dict(setup_payload)
        for key in ("hostname", "port", "urlBase", "useSsl"):
            retry_payload.pop(key, None)
        public_client.request(
            "POST", "/api/v1/auth/jellyfin", expected={200}, json_body=retry_payload
        )

    api_client = ApiClient(
        base_url=values["seerr"]["url"],
        default_headers={"X-Api-Key": env("SEERR_API_KEY")},
    )
    api_client.request("POST", "/api/v1/settings/initialize", expected={200})


def reconcile_seerr(values: dict[str, Any]) -> None:
    maybe_bootstrap_seerr(values)

    client = ApiClient(
        base_url=values["seerr"]["url"],
        default_headers={"X-Api-Key": env("SEERR_API_KEY")},
    )

    wait_for(
        lambda: client.request("GET", "/api/v1/status", expected={200}) is not None,
        name="seerr api",
    )

    _, main_settings = client.request("GET", "/api/v1/settings/main", expected={200})
    main_payload = dict(main_settings) if isinstance(main_settings, dict) else {}
    main_payload["mediaServerType"] = 2
    client.request(
        "POST",
        "/api/v1/settings/main",
        expected={200},
        json_body=main_payload,
    )

    _, jellyfin_current = client.request(
        "GET", "/api/v1/settings/jellyfin", expected={200}
    )
    jellyfin_current_obj = (
        jellyfin_current if isinstance(jellyfin_current, dict) else {}
    )

    jellyfin = values["seerr"]["jellyfin"]
    jellyfin_api_key = maybe_env("SEERR_JELLYFIN_API_KEY") or maybe_env(
        "JELLYFIN_API_TOKEN"
    )
    if not jellyfin_api_key:
        jellyfin_api_key = ensure_jellyfin_token(values, required=False)
    if not jellyfin_api_key:
        existing_jellyfin_api_key = jellyfin_current_obj.get("apiKey")
        if isinstance(existing_jellyfin_api_key, str):
            jellyfin_api_key = existing_jellyfin_api_key.strip()
    if not jellyfin_api_key and value_present(maybe_env("JELLYFIN_ADMIN_PASSWORD")):
        jellyfin_api_key = ensure_jellyfin_token(values, required=True)
    if not jellyfin_api_key:
        raise RuntimeError(
            "missing jellyfin api key for seerr; set SEERR_JELLYFIN_API_KEY "
            "or JELLYFIN_API_TOKEN in homelab-reconcile-env"
        )
    if not value_present(maybe_env("JELLYFIN_API_TOKEN")):
        os.environ["JELLYFIN_API_TOKEN"] = jellyfin_api_key

    jellyfin_payload = {
        "ip": jellyfin["ip"],
        "port": jellyfin["port"],
        "useSsl": jellyfin["useSsl"],
        "urlBase": jellyfin["urlBase"],
        "apiKey": jellyfin_api_key,
        "externalHostname": jellyfin["externalHostname"],
        "jellyfinForgotPasswordUrl": jellyfin["jellyfinForgotPasswordUrl"],
    }
    for copy_key in ("name", "serverId"):
        existing_value = jellyfin_current_obj.get(copy_key)
        if isinstance(existing_value, str) and existing_value.strip():
            jellyfin_payload[copy_key] = existing_value

    client.request(
        "POST",
        "/api/v1/settings/jellyfin",
        expected={200, 201, 204},
        json_body=jellyfin_payload,
    )

    _, jellyfin_libraries = client.request(
        "GET", "/api/v1/settings/jellyfin/library?sync=true", expected={200}
    )
    jellyfin_libraries_list = (
        jellyfin_libraries if isinstance(jellyfin_libraries, list) else []
    )

    enabled_library_names = set(jellyfin.get("enabledLibraries", []))
    enabled_library_ids: list[str] = []
    for library in jellyfin_libraries_list:
        if not isinstance(library, dict):
            continue
        name = library.get("name")
        lib_id = library.get("id")
        if (
            isinstance(name, str)
            and name in enabled_library_names
            and isinstance(lib_id, str)
        ):
            enabled_library_ids.append(lib_id)

    if enabled_library_names and not enabled_library_ids:
        raise RuntimeError(
            "seerr jellyfin libraries sync returned no matching libraries for "
            f"{sorted(enabled_library_names)}"
        )

    if enabled_library_ids:
        encoded_ids = urllib.parse.quote(",".join(enabled_library_ids), safe=",")
        client.request(
            "GET",
            f"/api/v1/settings/jellyfin/library?enable={encoded_ids}",
            expected={200},
        )

    client.request(
        "POST",
        "/api/v1/settings/jellyfin/sync",
        expected={200},
        json_body={"start": True},
    )

    for arr_name in ("radarr", "sonarr"):
        arr = values["arr"][arr_name]
        arr_cfg = values["seerr"][arr_name]
        test_payload = {
            "hostname": arr["host"],
            "port": arr["port"],
            "apiKey": env(f"{arr_name.upper()}_API_KEY"),
            "useSsl": False,
            "baseUrl": "",
        }
        _, test_resp = client.request(
            "POST",
            f"/api/v1/settings/{arr_name}/test",
            expected={200},
            json_body=test_payload,
        )
        profile_id = pick_profile_id(test_resp if isinstance(test_resp, dict) else {})

        server_payload = {
            "name": arr_cfg["name"],
            "hostname": arr["host"],
            "port": arr["port"],
            "apiKey": env(f"{arr_name.upper()}_API_KEY"),
            "useSsl": False,
            "baseUrl": "",
            "activeProfileId": profile_id,
            "activeDirectory": arr_cfg["activeDirectory"],
            "isDefault": arr_cfg["isDefault"],
            "is4k": arr_cfg["is4k"],
            "syncEnabled": arr_cfg["syncEnabled"],
            "preventSearch": arr_cfg["preventSearch"],
        }

        upsert_named(
            client,
            list_path=f"/api/v1/settings/{arr_name}",
            create_path=f"/api/v1/settings/{arr_name}",
            update_path_prefix=f"/api/v1/settings/{arr_name}",
            name=arr_cfg["name"],
            payload=server_payload,
        )


def reconcile_jellyfin(values: dict[str, Any]) -> None:
    token = ensure_jellyfin_token(values, required=True)
    assert token is not None

    client = ApiClient(
        base_url=values["jellyfin"]["url"],
        default_headers={"Authorization": f'MediaBrowser Token="{token}"'},
    )

    wait_for(
        lambda: client.request("GET", "/System/Info", expected={200}) is not None,
        name="jellyfin api",
    )

    _, folders = client.request("GET", "/Library/VirtualFolders", expected={200})
    existing = {
        item.get("Name")
        for item in folders
        if isinstance(item, dict) and isinstance(item.get("Name"), str)
    }

    for library in values["jellyfin"]["libraries"]:
        if library["name"] in existing:
            continue
        query = urllib.parse.urlencode({
            "name": library["name"],
            "collectionType": library["collectionType"],
            "refreshLibrary": "true",
        })
        payload = {
            "LibraryOptions": {
                "pathInfos": [{"Path": path} for path in library["paths"]],
            }
        }
        client.request(
            "POST",
            f"/Library/VirtualFolders?{query}",
            expected={200, 204},
            json_body=payload,
        )


def main() -> None:
    values = json.loads(env("HOMELAB_INTEGRATION_VALUES"))
    if not isinstance(values, dict):
        raise RuntimeError("HOMELAB_INTEGRATION_VALUES must decode to an object")

    maybe_configure_servarr_env_api_keys()
    maybe_raise_api_key_bootstrap_error()
    ensure_seerr_api_key()

    ensure_required_env_vars([
        "PROWLARR_API_KEY",
        "SONARR_API_KEY",
        "RADARR_API_KEY",
        "LIDARR_API_KEY",
        "READARR_API_KEY",
        "SEERR_API_KEY",
        "QBITTORRENT_USERNAME",
        "QBITTORRENT_PASSWORD",
        "NZBGET_USERNAME",
        "NZBGET_PASSWORD",
    ])

    started = datetime.now(UTC)
    state: dict[str, Any] = {
        "ok": False,
        "startedAt": started.isoformat(),
        "profile": values.get("profile", "unknown"),
    }

    reconcile_prowlarr(values, state)
    reconcile_arr(values, state)
    reconcile_seerr(values)
    reconcile_jellyfin(values)

    state["ok"] = True
    state["completedAt"] = datetime.now(UTC).isoformat()

    state_dir = pathlib.Path("/var/lib/homelab-reconcile")
    state_dir.mkdir(parents=True, exist_ok=True)
    (state_dir / "state.json").write_text(
        json.dumps(state, sort_keys=True) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
