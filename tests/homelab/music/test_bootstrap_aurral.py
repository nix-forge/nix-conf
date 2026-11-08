"""Aurral's first-run bootstrap uses the intended private integrations."""

from __future__ import annotations

import copy
import importlib.util
import io
import json
import sys
from pathlib import Path
from typing import TYPE_CHECKING, Any
from unittest.mock import Mock
from urllib.error import URLError
from urllib.parse import urlparse

import pytest

if TYPE_CHECKING:
    from types import ModuleType

SCRIPT = (
    Path(__file__).resolve().parents[3]
    / "hosts/nixos/desktop/local/homelab/music/scripts/bootstrap_aurral.py"
)


def load_bootstrap(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> tuple[ModuleType, Path, Path]:
    """Load the bootstrap with isolated credentials and replace network readiness.

    Returns:
        The loaded module, state directory and download directory.

    """
    credentials = tmp_path / "credentials"
    credentials.mkdir()
    (credentials / "lidarr-api-key").write_text("sealed-key\n")
    (credentials / "aurral-admin-username").write_text("reader-admin\n")
    (credentials / "aurral-admin-password").write_text("existing-password\n")
    (credentials / "listenbrainz-identity").write_text(
        json.dumps({"listenbrainzUsername": "listener"})
    )
    (credentials / "slskd-settings").write_text("SLSKD_API_KEY=soulseek-key\n")
    state = tmp_path / "state"
    state.mkdir()
    downloads = tmp_path / "music"
    downloads.mkdir()
    music_root = tmp_path / "library"
    music_root.mkdir()
    monkeypatch.setenv("CREDENTIALS_DIRECTORY", str(credentials))
    monkeypatch.setenv("AURRAL_URL", "http://127.0.0.1:13001")
    monkeypatch.setenv("LIDARR_URL", "http://127.0.0.1:18686")
    monkeypatch.setenv("SLSKD_URL", "http://169.254.202.94:5030")
    monkeypatch.setenv("AURRAL_DATA_DIR", str(state))
    policy = tmp_path / "quality-policy.json"
    policy.write_text(
        json.dumps({
            "name": "Aurral High Quality",
            "templateName": "Lossless",
            "onboarding": {
                "metadataProfileName": "Standard",
                "defaultMonitorOption": "future",
                "searchOnAdd": True,
                "localNetworkBypass": False,
            },
            "slskd": {
                "priority": 10,
                "preferredFormat": "flac",
                "preferredFormatStrict": False,
            },
            "cutoffQualityName": None,
            "upgradeAllowed": False,
            "allowedQualityNames": [
                "FLAC",
                "FLAC 24bit",
                "ALAC",
                "ALAC 24bit",
                "MP3-320",
                "MP3-256",
                "MP3-VBR-V0",
                "AAC-320",
                "AAC-256",
                "AAC-VBR",
            ],
        })
    )
    monkeypatch.setenv("AURRAL_QUALITY_POLICY", str(policy))
    monkeypatch.setattr(sys, "argv", [str(SCRIPT), str(downloads), str(music_root)])
    spec = importlib.util.spec_from_file_location("bootstrap_aurral_test", SCRIPT)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    monkeypatch.setattr(module, "wait_for_aurral", lambda: None)
    return module, state, downloads


def test_lidarr_root_fails_once_for_systemd_retry(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    """Verify lidarr root fails once for systemd retry."""
    module, _, _ = load_bootstrap(monkeypatch, tmp_path)
    attempts = []

    def unavailable_request(url: str, **kwargs: Any) -> None:
        attempts.append(url)
        raise URLError("connection refused")

    monkeypatch.setattr(module, "request", unavailable_request)
    with pytest.raises(URLError):
        module.lidarr_music_root("sealed-key")
    assert len(attempts) == 1


@pytest.mark.parametrize("custom_policy", [False, True])
def test_first_run_creates_admin_and_links_personal_history(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path, custom_policy: bool
) -> None:
    """Verify first run creates admin and links personal history."""
    module, state, downloads = load_bootstrap(monkeypatch, tmp_path)
    if custom_policy:
        module.QUALITY_POLICY["onboarding"].update(
            defaultMonitorOption="all", searchOnAdd=False, localNetworkBypass=True
        )
        module.QUALITY_POLICY["slskd"].update(
            priority=20, preferredFormat="mp3", preferredFormatStrict=True
        )
    calls = []
    monkeypatch.setattr(module, "configure_lidarr_quality", lambda *args: None)

    def fake_request(
        url: str,
        *,
        method: str = "GET",
        payload: Any = None,
        headers: Any = None,
        timeout: float = 10,
    ) -> Any:
        path = urlparse(url).path
        calls.append((path, method, payload, headers or {}))
        if path == "/api/health/bootstrap":
            return {"onboardingRequired": True}
        if path == "/api/v1/qualityprofile":
            assert headers["X-Api-Key"] == "sealed-key"
            return (
                [
                    {
                        "id": 8,
                        "name": "Lossless",
                        "cutoff": 6,
                        "items": [
                            {"quality": {"id": 6, "name": "FLAC"}, "allowed": True}
                        ],
                    }
                ]
                if method == "GET"
                else {"id": 8}
            )
        if path == "/api/v1/metadataprofile":
            return [{"id": 3, "name": "Standard"}]
        if path == "/api/v1/rootfolder":
            return [{"path": str(module.MUSIC_ROOT)}]
        if path == "/api/onboarding/complete":
            assert payload["lidarr"]["qualityProfileId"] == 8
            assert payload["lidarr"]["metadataProfileId"] == 3
            assert payload["lidarr"]["rootFolderPaths"] == [str(module.MUSIC_ROOT)]
            assert payload["downloadFolderPath"] == str(downloads)
            assert payload["security"]["localNetworkBypass"]["enabled"] == custom_policy
            assert payload["lidarr"]["searchOnAdd"] == (not custom_policy)
            assert payload["lidarr"]["defaultMonitorOption"] == (
                "all" if custom_policy else "future"
            )
            return {"success": True}
        if path == "/api/auth/login":
            assert payload["username"] == "reader-admin"
            assert payload["password"] == "existing-password"
            return {"token": "session", "user": {"id": 5}}
        if path == "/api/users/me/listening-history":
            assert method == "PATCH"
            assert headers["Authorization"] == "Bearer session"
            assert payload == {"listenbrainz": "listener"}
            return {
                "listenbrainz": "listener",
                "lastfm": "other-listener",
                "koito": None,
            }
        if path == "/api/settings":
            assert headers["Authorization"] == "Bearer session"
            if method == "GET":
                return {
                    "downloadFolderPath": str(downloads),
                    "integrations": {
                        "lidarr": {"rootFolderPaths": [str(module.MUSIC_ROOT)]}
                    },
                }
            assert payload["integrations"]["slskd"] == {
                "enabled": True,
                "url": "http://169.254.202.94:5030",
                "apiKey": "soulseek-key",
                **module.QUALITY_POLICY["slskd"],
            }
            return {"success": True}
        if path == "/api/library/refresh":
            assert method == "POST"
            return {"queued": True}
        raise AssertionError(f"Unexpected request: {path}")

    monkeypatch.setattr(module, "request", fake_request)
    module.main()

    assert not (state / "admin-password").exists()
    assert (state / "listenbrainz-profile").read_text() == "listener\n"
    assert (state / "slskd-profile").exists()
    assert (state / "library-metadata-version").read_text() == "shared-music-root-v2\n"
    assert [call[0] for call in calls] == [
        "/api/v1/rootfolder",
        "/api/health/bootstrap",
        "/api/v1/qualityprofile",
        "/api/v1/qualityprofile",
        "/api/v1/metadataprofile",
        "/api/onboarding/complete",
        "/api/auth/login",
        "/api/settings",
        "/api/users/me/listening-history",
        "/api/settings",
        "/api/library/refresh",
    ]


def test_existing_setup_does_not_reset_credentials(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    """Verify existing setup does not reset credentials."""
    module, state, downloads = load_bootstrap(monkeypatch, tmp_path)
    password = state / "admin-password"
    password.write_text("obsolete-local-password\n")
    (state / "listenbrainz-profile").write_text("listener\n")
    key = module.slskd_api_key()
    fingerprint = module.hashlib.sha256(
        (module.SLSKD + "\0" + key).encode()
    ).hexdigest()
    (state / "slskd-profile").write_text(fingerprint + "\n")
    calls = []
    monkeypatch.setattr(module, "configure_lidarr_quality", lambda *args: None)

    def fake_request(
        url: str,
        *,
        method: str = "GET",
        payload: Any = None,
        headers: Any = None,
        timeout: float = 10,
    ) -> Any:
        path = urlparse(url).path
        calls.append((path, method, payload))
        if path == "/api/v1/rootfolder":
            return [{"path": str(module.MUSIC_ROOT)}]
        if path == "/api/health/bootstrap":
            return {"onboardingRequired": False}
        if path == "/api/auth/login":
            assert payload["password"] == "existing-password"
            return {"token": "session", "user": {"id": 5}}
        if path == "/api/settings":
            if method == "GET":
                return {"integrations": {"lidarr": {"rootFolderPaths": []}}}
            assert payload in [
                {"downloadFolderPath": str(downloads)},
                {
                    "integrations": {
                        "lidarr": {"rootFolderPaths": [str(module.MUSIC_ROOT)]}
                    }
                },
            ]
            return {"success": True}
        if path == "/api/library/refresh":
            assert method == "POST"
            return {"queued": True}
        if path == "/api/users/5":
            return {"id": 5}
        raise AssertionError(f"Unexpected request: {path}")

    monkeypatch.setattr(module, "request", fake_request)
    module.main()
    assert password.read_text() == "obsolete-local-password\n"
    assert (state / "library-metadata-version").read_text() == "shared-music-root-v2\n"
    assert [(path, method) for path, method, _ in calls] == [
        ("/api/v1/rootfolder", "GET"),
        ("/api/health/bootstrap", "GET"),
        ("/api/auth/login", "POST"),
        ("/api/settings", "GET"),
        ("/api/settings", "POST"),
        ("/api/settings", "POST"),
        ("/api/library/refresh", "POST"),
    ]


def test_scrobbling_validates_identity_and_skips_unchanged_token(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    """Verify scrobbling validates identity and skips unchanged token."""
    module, state, _ = load_bootstrap(monkeypatch, tmp_path)
    identity = {"listenbrainzUsername": "listener", "token": "private-fixture-token"}
    calls = []
    monkeypatch.setattr(module, "configure_lidarr_quality", lambda *args: None)

    def fake_request(url: str, **kwargs: Any) -> Any:
        calls.append((urlparse(url).path, kwargs))
        if url.endswith("/status"):
            return {"listenbrainz": {"connected": True, "displayName": "listener"}}
        assert kwargs["payload"] == {
            "token": "private-fixture-token",
            "expectedUsername": "listener",
        }
        return {"connected": True, "displayName": "listener"}

    monkeypatch.setattr(module, "request", fake_request)
    module.configure_listenbrainz_scrobbling(
        identity, {"Authorization": "Bearer session"}
    )
    module.configure_listenbrainz_scrobbling(
        identity, {"Authorization": "Bearer session"}
    )
    assert [path for path, _ in calls] == [
        "/api/scrobbling/status",
        "/api/scrobbling/listenbrainz/link",
        "/api/scrobbling/status",
    ]
    assert (
        "private-fixture-token"
        not in (state / "listenbrainz-scrobbling-profile").read_text()
    )


def test_scrobbling_does_not_mark_wrong_identity_ready(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    """Verify scrobbling does not mark wrong identity ready."""
    module, state, _ = load_bootstrap(monkeypatch, tmp_path)

    def fake_request(url: str, **kwargs: Any) -> Any:
        return (
            {"listenbrainz": {}}
            if url.endswith("/status")
            else {"connected": True, "displayName": "other"}
        )

    monkeypatch.setattr(module, "request", fake_request)
    with pytest.raises(RuntimeError, match="verification"):
        module.configure_listenbrainz_scrobbling(
            {"listenbrainzUsername": "listener", "token": "fixture"}, {}
        )
    assert not (state / "listenbrainz-scrobbling-profile").exists()


def test_quality_policy_allows_fallback_without_low_quality(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    """Verify quality policy allows fallback without low quality."""
    module, _, _ = load_bootstrap(monkeypatch, tmp_path)
    template = {
        "id": 2,
        "name": "Lossless",
        "upgradeAllowed": False,
        "cutoff": 1005,
        "items": [
            {"quality": {"id": 0, "name": "Unknown"}, "allowed": False},
            {
                "id": 1004,
                "name": "High Quality Lossy",
                "allowed": False,
                "items": [{"quality": {"id": 4, "name": "MP3-320"}, "allowed": False}],
            },
            {"quality": {"id": 22, "name": "MP3-128"}, "allowed": False},
            {
                "id": 1005,
                "name": "Lossless",
                "allowed": True,
                "items": [{"quality": {"id": 6, "name": "FLAC"}, "allowed": True}],
            },
        ],
    }
    profiles = [template]
    writes = []

    def api(
        url: str, *, method: str = "GET", payload: Any = None, **kwargs: Any
    ) -> Any:
        if method == "GET":
            return profiles
        writes.append(payload)
        saved = {**payload, "id": 9}
        profiles.append(saved)
        return saved

    monkeypatch.setattr(module, "request", api)
    assert module.ensure_quality_profile("key") == 9
    policy = writes[0]
    assert policy["name"] == "Aurral High Quality"
    assert policy["items"][1]["allowed"]
    assert policy["items"][1]["items"][0]["allowed"]
    assert policy["items"][3]["items"][0]["allowed"]
    assert not policy["items"][0]["allowed"]
    assert not policy["items"][2]["allowed"]
    assert not policy["upgradeAllowed"]
    profiles[:] = [profiles[-1]]  # The unused stock profile may be removed.
    assert module.ensure_quality_profile("key") == 9
    assert len(writes) == 1
    assert not template["items"][1]["allowed"]


def test_quality_migration_preserves_other_artists_and_retries(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    """Verify quality migration preserves other artists and retries."""
    module, state, _ = load_bootstrap(monkeypatch, tmp_path)
    artists = [
        {"id": 1, "path": str(module.MUSIC_ROOT / "Artist"), "qualityProfileId": 2},
        {"id": 2, "path": str(module.MUSIC_ROOT / "Custom"), "qualityProfileId": 7},
        {"id": 3, "path": "/another/library/Artist", "qualityProfileId": 2},
    ]
    writes = []
    monkeypatch.setattr(module, "ensure_quality_profile", lambda key: 9)

    def api(
        url: str, *, method: str = "GET", payload: Any = None, **kwargs: Any
    ) -> Any:
        if url.endswith("/qualityprofile"):
            return [{"id": 2, "name": "Lossless"}]
        if url.endswith("/artist"):
            return artists
        writes.append((url, payload))
        return {}

    monkeypatch.setattr(module, "request", api)
    module.configure_lidarr_quality("key", {"qualityProfileId": 2}, {})
    assert len(writes) == 2
    assert writes[0][0].endswith("/artist/1")
    assert writes[0][1]["qualityProfileId"] == 9
    assert writes[1][1] == {"integrations": {"lidarr": {"qualityProfileId": 9}}}
    module.configure_lidarr_quality("key", {"qualityProfileId": 9}, {})
    assert len(writes) == 2
    assert (state / "lidarr-quality-profile-v1").read_text() == "9\n"


def test_quality_migration_does_not_mark_failed_artist_update_complete(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    """Verify quality migration does not mark failed artist update complete."""
    module, state, _ = load_bootstrap(monkeypatch, tmp_path)
    monkeypatch.setattr(module, "ensure_quality_profile", lambda key: 9)
    writes = []

    def api(
        url: str, *, method: str = "GET", payload: Any = None, **kwargs: Any
    ) -> Any:
        if url.endswith("/qualityprofile"):
            return [{"id": 2, "name": "Lossless"}]
        if url.endswith("/artist"):
            return [
                {
                    "id": 1,
                    "path": str(module.MUSIC_ROOT / "Artist"),
                    "qualityProfileId": 2,
                }
            ]
        writes.append(url)
        raise URLError("temporary outage")

    monkeypatch.setattr(module, "request", api)
    with pytest.raises(URLError):
        module.configure_lidarr_quality("key", {"qualityProfileId": 2}, {})
    assert writes == [f"{module.LIDARR}/api/v1/artist/1"]
    assert not (state / "lidarr-quality-profile-v1").exists()


def test_quality_migration_keeps_custom_default(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    """Verify quality migration keeps custom default."""
    module, state, _ = load_bootstrap(monkeypatch, tmp_path)

    def api(url: str, **kwargs: Any) -> Any:
        assert url.endswith("/qualityprofile")
        return [{"id": 7, "name": "My archival policy"}]

    monkeypatch.setattr(module, "request", api)
    module.configure_lidarr_quality("key", {"qualityProfileId": 7}, {})
    assert not (state / "lidarr-quality-profile-v1").exists()


def test_empty_successful_api_response(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    """Verify empty successful api response."""
    module, _, _ = load_bootstrap(monkeypatch, tmp_path)
    monkeypatch.setattr(
        module.urllib.request, "urlopen", lambda *a, **kw: io.BytesIO(b"")
    )
    assert module.request("http://localhost/test", method="POST", payload={}) is None


def test_import_webhook_uses_persistent_key_and_is_idempotent(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    """Verify import webhook uses persistent key and is idempotent."""
    module, _, _ = load_bootstrap(monkeypatch, tmp_path)
    saved = []
    calls = []
    schema = {
        "implementation": "Webhook",
        "fields": [{"name": "url"}, {"name": "method"}, {"name": "headers"}],
    }

    def api(
        url: str,
        *,
        method: str = "GET",
        payload: Any = None,
        headers: Any = None,
    ) -> Any:
        calls.append((url, method))
        if url.endswith("/api/auth/api-key"):
            assert headers == {"Authorization": "Bearer temporary-session"}
            return {"apiKey": "persistent-key"}
        assert headers == {"X-Api-Key": "lidarr-key"}
        if url.endswith("/schema"):
            return [schema]
        if url.endswith("/test"):
            fields = {f["name"]: f["value"] for f in payload["fields"]}
            assert fields["headers"] == [
                {"key": "X-Api-Key", "value": "persistent-key"}
            ]
            assert fields["url"].endswith("/api/webhooks/lidarr")
            return None
        if method == "GET":
            return saved
        saved.append({**copy.deepcopy(payload), "id": 1})
        return saved[-1]

    monkeypatch.setattr(module, "request", api)
    for _ in range(2):
        module.configure_import_webhook(
            "lidarr-key", {"Authorization": "Bearer temporary-session"}
        )
    assert len(saved) == 1
    assert (
        sum(method == "POST" and not url.endswith("/test") for url, method in calls)
        == 1
    )


def test_navidrome_connection_validated_before_saving(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    """Verify navidrome connection validated before saving."""
    module, state, _ = load_bootstrap(monkeypatch, tmp_path)
    monkeypatch.setenv("NAVIDROME_URL", "http://127.0.0.1:4533")
    (module.CREDENTIALS / "navidrome-service-username").write_text("music-service")
    (module.CREDENTIALS / "navidrome-settings").write_text(
        "NAVIDROME_SERVICE_PASSWORD='private password'\n"
    )
    calls = []

    def failing(url: str, **kwargs: Any) -> None:
        calls.append(url)
        raise URLError("unreachable")

    monkeypatch.setattr(module, "request", failing)
    with pytest.raises(URLError):
        module.configure_navidrome({})
    assert len(calls) == 1
    assert not (state / "navidrome-profile").exists()


def test_quality_initialization_uses_service_readiness_without_aurral(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    """Verify quality initialization waits for lidarr without aurral."""
    module, _, _ = load_bootstrap(monkeypatch, tmp_path)
    monkeypatch.setenv("AURRAL_QUALITY_ONLY", "1")
    api = Mock(side_effect=AssertionError("readiness belongs to the service"))
    profile = Mock()
    aurral = Mock(side_effect=AssertionError("must not depend on Aurral"))
    monkeypatch.setattr(module, "request", api)
    monkeypatch.setattr(module, "ensure_quality_profile", profile)
    monkeypatch.setattr(module, "wait_for_aurral", aurral)
    module.main()
    api.assert_not_called()
    profile.assert_called_once_with("sealed-key")
    aurral.assert_not_called()


def test_alternate_quality_policy(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    """Use the selected name, template, formats and upgrade policy."""
    module, _, _ = load_bootstrap(monkeypatch, tmp_path)
    module.QUALITY_POLICY.update(
        name="Portable",
        templateName="Custom template",
        allowedQualityNames=["MP3-128"],
        upgradeAllowed=True,
        cutoffQualityName="MP3-128",
    )
    monkeypatch.setattr(module, "QUALITY_PROFILE_NAME", module.QUALITY_POLICY["name"])
    template = {
        "id": 2,
        "name": "Custom template",
        "cutoff": 22,
        "items": [
            {"quality": {"id": 22, "name": "MP3-128"}, "allowed": False},
            {"quality": {"id": 6, "name": "FLAC"}, "allowed": True},
        ],
    }
    writes = []

    def api(url: str, **kwargs: Any) -> Any:
        if kwargs.get("method", "GET") == "GET":
            return [template]
        writes.append(kwargs["payload"])
        return {"id": 9}

    monkeypatch.setattr(module, "request", api)
    assert module.ensure_quality_profile("key") == 9
    assert writes[0]["name"] == "Portable"
    assert writes[0]["upgradeAllowed"] is True
    assert writes[0]["cutoff"] == 22
    assert [item["allowed"] for item in writes[0]["items"]] == [True, False]
    assert template["items"][0]["allowed"] is False


def test_quality_rename_migrates_only_owned_profile(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    """A policy rename follows the prior managed identifier and preserves custom defaults."""
    module, state, _ = load_bootstrap(monkeypatch, tmp_path)
    (state / "lidarr-quality-profile-v1").write_text("8\n")
    monkeypatch.setattr(module, "QUALITY_PROFILE_NAME", "Renamed policy")
    writes = []

    def api(url: str, **kwargs: Any) -> Any:
        if url.endswith("/qualityprofile"):
            return [{"id": 8, "name": "Prior managed name"}]
        if url.endswith("/artist"):
            return [
                {
                    "id": 1,
                    "path": str(module.MUSIC_ROOT / "Artist"),
                    "qualityProfileId": 8,
                }
            ]
        writes.append(kwargs["payload"])
        return {}

    monkeypatch.setattr(module, "request", api)
    monkeypatch.setattr(module, "ensure_quality_profile", lambda key: 9)
    module.configure_lidarr_quality("key", {"qualityProfileId": 7}, {})
    assert writes == []
    module.configure_lidarr_quality("key", {"qualityProfileId": 8}, {})
    assert writes[0]["qualityProfileId"] == 9
    assert writes[1] == {"integrations": {"lidarr": {"qualityProfileId": 9}}}
    assert (state / "lidarr-quality-profile-v1").read_text() == "9\n"


def test_grouped_quality_cutoff_uses_top_level_group(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    """Lidarr validates cutoff identifiers against top-level profile items."""
    module, _, _ = load_bootstrap(monkeypatch, tmp_path)
    module.QUALITY_POLICY["cutoffQualityName"] = "FLAC"
    template = {
        "id": 2,
        "name": "Lossless",
        "cutoff": 1004,
        "items": [
            {
                "id": 1005,
                "name": "Lossless",
                "allowed": True,
                "items": [{"quality": {"id": 6, "name": "FLAC"}, "allowed": True}],
            }
        ],
    }
    writes = []

    def api(url: str, **kwargs: Any) -> Any:
        if kwargs.get("method", "GET") == "GET":
            return [template]
        writes.append(kwargs["payload"])
        return {"id": 9}

    monkeypatch.setattr(module, "request", api)
    assert module.ensure_quality_profile("key") == 9
    assert writes[0]["cutoff"] == 1005
    module.QUALITY_POLICY["cutoffQualityName"] = "Missing format"
    with pytest.raises(RuntimeError, match="missing"):
        module.ensure_quality_profile("key")
    assert len(writes) == 1


def test_zero_quality_identifier_is_valid(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    """A selected zero identifier is a quality, not a missing value."""
    module, _, _ = load_bootstrap(monkeypatch, tmp_path)
    module.QUALITY_POLICY.update(
        cutoffQualityName="Unknown", allowedQualityNames=["Unknown"]
    )
    template = {
        "id": 2,
        "name": "Lossless",
        "cutoff": 0,
        "items": [
            {"quality": {"id": 0, "name": "Unknown"}, "allowed": False},
        ],
    }
    writes = []

    def api(url: str, **kwargs: Any) -> Any:
        if kwargs.get("method", "GET") == "GET":
            return [template]
        writes.append(kwargs["payload"])
        return {"id": 9}

    monkeypatch.setattr(module, "request", api)
    assert module.ensure_quality_profile("key") == 9
    assert writes[0]["cutoff"] == 0


def test_selected_metadata_profile_is_required(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    """Use the exact selected profile and reject an unrelated fallback."""
    module, _, _ = load_bootstrap(monkeypatch, tmp_path)
    module.QUALITY_POLICY["onboarding"]["metadataProfileName"] = "Custom metadata"
    monkeypatch.setattr(
        module,
        "request",
        lambda *args, **kwargs: [
            {"id": 1, "name": "Standard"},
            {"id": 7, "name": "Custom metadata"},
        ],
    )
    assert module.preferred_profile("key", "metadataprofile") == 7
    module.QUALITY_POLICY["onboarding"]["metadataProfileName"] = "Missing"
    with pytest.raises(RuntimeError, match="missing"):
        module.preferred_profile("key", "metadataprofile")


@pytest.mark.parametrize("prior_marker", [False, True])
def test_slskd_connection_refresh_preserves_ui_settings(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path, prior_marker: bool
) -> None:
    """Rotating connection credentials must preserve established acquisition choices."""
    module, state, downloads = load_bootstrap(monkeypatch, tmp_path)
    (state / "listenbrainz-profile").write_text("listener\n")
    (state / "library-metadata-version").write_text(module.LIBRARY_METADATA_VERSION)
    if prior_marker:
        (state / "slskd-profile").write_text("old-key-fingerprint")
    saved = {
        "enabled": False,
        "url": "http://previous:5030",
        "apiKey": "old-key",
        "priority": 23,
        "preferredFormat": "mp3",
        "preferredFormatStrict": True,
    }
    writes = []
    monkeypatch.setattr(module, "configure_lidarr_quality", lambda *args: None)

    def api(url: str, **kwargs: Any) -> Any:
        path = urlparse(url).path
        if path == "/api/v1/rootfolder":
            return [{"path": str(module.MUSIC_ROOT)}]
        if path == "/api/health/bootstrap":
            return {"onboardingRequired": False}
        if path == "/api/auth/login":
            return {"token": "session", "user": {"id": 5}}
        if path == "/api/settings":
            if kwargs.get("method", "GET") == "GET":
                return {
                    "downloadFolderPath": str(downloads),
                    "integrations": {
                        "slskd": saved,
                        "lidarr": {"rootFolderPaths": [str(module.MUSIC_ROOT)]},
                    },
                }
            writes.append(kwargs["payload"])
            return {}
        raise AssertionError(path)

    monkeypatch.setattr(module, "request", api)
    module.main()
    assert writes == [
        {
            "integrations": {
                "slskd": {**saved, "url": module.SLSKD, "apiKey": "soulseek-key"}
            }
        }
    ]
    assert saved["apiKey"] == "old-key"
    assert (state / "slskd-profile").read_text().strip() != "old-key-fingerprint"


@pytest.mark.parametrize("response", [None, {}, {"listenbrainz": "other-listener"}])
def test_history_requires_confirmed_account_before_ready_marker(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path, response: Any
) -> None:
    """Reject ignored or mismatched history writes without marking them ready."""
    module, state, _ = load_bootstrap(monkeypatch, tmp_path)
    request = Mock(return_value=response)
    monkeypatch.setattr(module, "request", request)
    with pytest.raises(RuntimeError, match="history account was not confirmed"):
        module.configure_listening_history(
            "listener", {"Authorization": "Bearer session"}
        )
    assert not (state / "listenbrainz-profile").exists()
