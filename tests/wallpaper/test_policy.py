"""Exercise operator preferences and cached provenance through the policy CLI."""

from __future__ import annotations

import json
import os
import runpy
import subprocess  # ruff: ignore[suspicious-subprocess-import] - isolated CLI fixture
import sys
import tracemalloc
from dataclasses import dataclass
from pathlib import Path
from types import SimpleNamespace
from typing import Any

import pytest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "modules/home/desktop/scripts/wallpaper-policy.py"


@dataclass
class Policy:
    """Run the real command with an independent catalog and private settings."""

    root: Path

    def run(
        self, *arguments: str, stdin: bytes | None = None
    ) -> subprocess.CompletedProcess[bytes]:
        """Capture the caller-visible exit status, JSON and diagnostics.

        Returns:
            Completed CLI process with unmodified stdout and stderr.

        """
        return subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - absolute interpreter, private fixture inputs
            [
                sys.executable,
                str(SCRIPT),
                "--catalog",
                str(self.root / "catalog.json"),
                "--config",
                str(self.root / "config.json"),
                "--preferences",
                str(self.root / "runtime" / "preferences.json"),
                *arguments,
            ],
            input=stdin,
            capture_output=True,
            check=False,
        )

    def command(self, *arguments: str) -> Any:  # ruff: ignore[any-type] - JSON command boundary
        """Require a successful command and decode its public result.

        Returns:
            Parsed JSON response from the operator command.

        """
        result = self.run(*arguments)
        assert result.returncode == 0, result.stderr.decode()
        return json.loads(result.stdout)

    def write(self, name: str, value: object) -> None:
        """Provide declarative or runtime settings without sharing source code."""
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value), encoding="utf-8")

    def image(self, name: str, metadata: object | None = None) -> Path:
        """Create a chooser candidate; decoding geometry belongs to the chooser.

        Returns:
            Candidate path with an optional source sidecar.

        """
        path = self.root / name
        path.write_bytes(b"fixture, deliberately not an encoded image")
        if metadata is not None:
            Path(str(path) + ".json").write_text(json.dumps(metadata), encoding="utf-8")
        return path


@pytest.fixture
def policy(tmp_path: Path) -> Policy:
    """Use five independent routes across three connections and three domains.

    Returns:
        Isolated CLI fixture with declarative settings and no runtime choices.

    """
    fixture = Policy(tmp_path)
    fixture.write(
        "catalog.json",
        {
            "connections": {"wikimediaCommons": {}, "esaHubble": {}, "esaWebb": {}},
            "categories": {
                "nature": {"subcategories": {"mountains": {}, "coasts": {}}},
                "cityscapes": {"subcategories": {"skylines": {}}},
                "space": {"subcategories": {"nebulae": {}}},
            },
            "routes": [
                {
                    "connection": "wikimediaCommons",
                    "category": "nature",
                    "subcategory": "mountains",
                    "collection": "Featured mountain photographs",
                },
                {
                    "connection": "wikimediaCommons",
                    "category": "nature",
                    "subcategory": "coasts",
                    "collection": "Featured coastal photographs",
                },
                {
                    "connection": "wikimediaCommons",
                    "category": "cityscapes",
                    "subcategory": "skylines",
                    "collection": "Featured skyline photographs",
                },
                {
                    "connection": "esaHubble",
                    "category": "space",
                    "subcategory": "nebulae",
                },
                {
                    "connection": "esaWebb",
                    "category": "space",
                    "subcategory": "nebulae",
                },
            ],
        },
    )
    fixture.write(
        "config.json",
        {
            "connections": {
                "wikimediaCommons": True,
                "esaHubble": True,
                "esaWebb": True,
            },
            "categories": {
                "nature": {
                    "enable": True,
                    "connections": {"wikimediaCommons": None},
                    "subcategories": {
                        "mountains": {"enable": True},
                        "coasts": {"enable": True},
                    },
                },
                "cityscapes": {
                    "enable": True,
                    "subcategories": {"skylines": {"enable": True}},
                },
                "space": {
                    "enable": True,
                    "subcategories": {"nebulae": {"enable": True}},
                },
            },
            "personal": True,
        },
    )
    return fixture


def route_names(routes: list[dict[str, str]]) -> set[str]:
    """Compare public route identities without freezing response ordering.

    Returns:
        Connection and category identities present in the command output.

    """
    return {
        f"{route['connection']}:{route['category']}/{route['subcategory']}"
        for route in routes
    }


def test_status_exposes_effective_settings_routes_and_catalog(policy: Policy) -> None:
    """A fresh process reports the settings used by both acquisition and rotation."""
    status = policy.command("status")
    assert status["settings"]["personal"] is True
    assert route_names(status["active_routes"]) == {
        "wikimediaCommons:nature/mountains",
        "wikimediaCommons:nature/coasts",
        "wikimediaCommons:cityscapes/skylines",
        "esaHubble:space/nebulae",
        "esaWebb:space/nebulae",
    }
    assert set(status["catalog"]["connections"]) == {
        "wikimediaCommons",
        "esaHubble",
        "esaWebb",
    }
    assert route_names(policy.command("plan", "esaWebb")) == {"esaWebb:space/nebulae"}


@pytest.mark.parametrize(
    ("commands", "expected"),
    [
        pytest.param(
            [
                ("connection", "wikimediaCommons", "off"),
                ("source", "wikimediaCommons", "nature/mountains", "on"),
            ],
            set(),
            id="global-source-off-is-hard-gate",
        ),
        pytest.param(
            [
                ("category", "nature", "off"),
                ("category", "nature/mountains", "on"),
                ("source", "wikimediaCommons", "nature/mountains", "on"),
            ],
            {"wikimediaCommons:cityscapes/skylines"},
            id="parent-off-is-hard-gate",
        ),
        pytest.param(
            [("category", "nature/coasts", "off")],
            {
                "wikimediaCommons:nature/mountains",
                "wikimediaCommons:cityscapes/skylines",
            },
            id="leaf-off-does-not-disable-sibling",
        ),
        pytest.param(
            [
                ("source", "wikimediaCommons", "nature", "off"),
                ("source", "wikimediaCommons", "nature/mountains", "on"),
            ],
            {
                "wikimediaCommons:nature/mountains",
                "wikimediaCommons:cityscapes/skylines",
            },
            id="nearest-source-override-wins",
        ),
        pytest.param(
            [
                ("source", "wikimediaCommons", "nature", "off"),
                ("source", "wikimediaCommons", "nature/mountains", "inherit"),
            ],
            {"wikimediaCommons:cityscapes/skylines"},
            id="leaf-null-inherits-parent-off",
        ),
        pytest.param(
            [("source", "wikimediaCommons", "nature", "inherit")],
            {
                "wikimediaCommons:nature/mountains",
                "wikimediaCommons:nature/coasts",
                "wikimediaCommons:cityscapes/skylines",
            },
            id="parent-null-inherits-global-on",
        ),
    ],
)
def test_precedence_controls_supported_routes(
    policy: Policy, commands: list[tuple[str, ...]], expected: set[str]
) -> None:
    """Hard gates and nearest overrides have distinct, observable effects."""
    for command in commands:
        policy.command(*command)
    assert route_names(policy.command("plan", "wikimediaCommons")) == expected
    assert route_names(policy.command("plan", "esaHubble")) == {
        "esaHubble:space/nebulae"
    }


def test_source_override_cannot_invent_unsupported_route(policy: Policy) -> None:
    """Enabling Hubble for nature never creates an adapter collection mapping."""
    policy.command("source", "esaHubble", "nature/mountains", "on")
    assert route_names(policy.command("plan", "esaHubble")) == {
        "esaHubble:space/nebulae"
    }


def test_runtime_default_removes_only_requested_override(policy: Policy) -> None:
    """Reset restores declarative defaults while preserving unrelated choices."""
    policy.command("connection", "esaWebb", "off")
    policy.command("category", "nature/coasts", "off")
    policy.command("personal", "off")
    policy.command("connection", "esaWebb", "default")
    preferences = json.loads(
        (policy.root / "runtime/preferences.json").read_text(encoding="utf-8")
    )
    assert "esaWebb" not in preferences.get("connections", {})
    assert preferences["personal"] is False
    assert (
        preferences["categories"]["nature"]["subcategories"]["coasts"]["enable"]
        is False
    )
    status = policy.command("status")
    assert status["settings"]["connections"]["esaWebb"] is True
    assert "wikimediaCommons:nature/coasts" not in route_names(status["active_routes"])


def test_inherit_differs_from_default_when_declarative_source_is_off(
    policy: Policy,
) -> None:
    """Runtime null removes the declared leaf choice; reset restores it."""
    defaults = json.loads((policy.root / "config.json").read_text(encoding="utf-8"))
    defaults["categories"]["nature"]["subcategories"]["mountains"]["connections"] = {
        "wikimediaCommons": False
    }
    policy.write("config.json", defaults)
    assert "wikimediaCommons:nature/mountains" not in route_names(
        policy.command("plan")
    )
    policy.command("source", "wikimediaCommons", "nature/mountains", "inherit")
    assert "wikimediaCommons:nature/mountains" in route_names(policy.command("plan"))
    policy.command("source", "wikimediaCommons", "nature/mountains", "default")
    assert "wikimediaCommons:nature/mountains" not in route_names(
        policy.command("plan")
    )
    saved = json.loads(
        (policy.root / "runtime/preferences.json").read_text(encoding="utf-8")
    )
    assert (
        "wikimediaCommons"
        not in saved["categories"]["nature"]["subcategories"]["mountains"][
            "connections"
        ]
    )


@pytest.mark.parametrize(
    "command",
    [
        ("plan", "unknown"),
        ("connection", "unknown", "off"),
        ("category", "unknown", "off"),
        ("category", "nature/unknown", "off"),
        ("category", "nature/mountains/extra", "off"),
        ("source", "unknown", "nature", "on"),
        ("source", "esaHubble", "unknown", "on"),
        ("connection", "esaWebb", "inherit"),
        ("personal", "inherit"),
    ],
)
def test_invalid_commands_fail_without_replacing_preferences(
    policy: Policy, command: tuple[str, ...]
) -> None:
    """Misspellings do not silently change or reset an existing user choice."""
    policy.command("personal", "off")
    path = policy.root / "runtime/preferences.json"
    before = path.read_bytes()
    result = policy.run(*command)
    assert result.returncode != 0
    assert result.stderr
    assert b"Traceback" not in result.stderr
    assert path.read_bytes() == before


@pytest.mark.parametrize("name", ["config.json", "runtime/preferences.json"])
@pytest.mark.parametrize(
    "invalid",
    [
        [],
        {"personal": 1},
        {"connections": {"esaWebb": "false"}},
        {"connections": {"esaWebb": None}},
        {"connections": {"unknown": True}},
        {"categories": {"nature": {"enable": 0}}},
        {"categories": {"nature": {"connections": {"esaHubble": "inherit"}}}},
        {"categories": {"nature": {"subcategories": {"missing": {"enable": True}}}}},
    ],
)
def test_invalid_persisted_types_and_names_fail_visibly(
    policy: Policy, name: str, invalid: object
) -> None:
    """Corrupt settings must not silently enable content or fall back to defaults."""
    policy.write(name, invalid)
    result = policy.run("status")
    assert result.returncode != 0
    assert b"Wallpaper preferences:" in result.stderr
    assert b"Traceback" not in result.stderr


def test_malformed_preferences_fail_visibly(policy: Policy) -> None:
    """A truncated runtime file is an error, not an empty preferences object."""
    policy.write("runtime/preferences.json", {})
    (policy.root / "runtime/preferences.json").write_text(
        '{"personal":', encoding="utf-8"
    )
    result = policy.run("plan")
    assert result.returncode != 0
    assert b"Wallpaper preferences:" in result.stderr


def test_commons_uses_collection_metadata_and_any_enabled_membership(
    policy: Policy,
) -> None:
    """An old cached file is classified by its source collections on every use."""
    candidate = policy.image(
        "wikimedia-commons-42.jpg",
        {
            "metadata": {
                "Categories": {
                    "value": "Featured_mountain_photographs|Featured coastal photographs|Unreviewed collection"
                }
            },
            "wallpaper_categories": ["space/nebulae"],
        },
    )
    assert policy.run("eligible", str(candidate)).returncode == 0
    policy.command("category", "nature/mountains", "off")
    assert policy.run("eligible", str(candidate)).returncode == 0
    policy.command("category", "nature/coasts", "off")
    assert policy.run("eligible", str(candidate)).returncode == 1


@pytest.mark.parametrize("connection", ["esaHubble", "esaWebb"])
def test_space_sidecar_rechecked_after_connection_and_category_changes(
    policy: Policy, connection: str
) -> None:
    """A cache hit cannot bypass a new global or category preference."""
    candidate = policy.image(
        "space-candidate.jpg",
        {"connection": connection, "wallpaper_categories": ["space/nebulae"]},
    )
    assert policy.run("eligible", str(candidate)).returncode == 0
    policy.command("connection", connection, "off")
    assert policy.run("eligible", str(candidate)).returncode == 1
    policy.command("connection", connection, "default")
    policy.command("category", "space", "off")
    assert policy.run("eligible", str(candidate)).returncode == 1


@pytest.mark.parametrize("prefix", ["wikimedia-commons-", "esa-hubble-", "esa-webb-"])
@pytest.mark.parametrize("contents", [None, "{", "[]", "{}"])
def test_provider_files_cannot_fall_back_to_personal_without_valid_provenance(
    policy: Policy, prefix: str, contents: str | None
) -> None:
    """Missing, corrupt and empty sidecars fail closed for every known provider."""
    candidate = policy.image(prefix + "old.jpg")
    if contents is not None:
        Path(str(candidate) + ".json").write_text(contents, encoding="utf-8")
    assert policy.run("eligible", str(candidate)).returncode == 1


@pytest.mark.parametrize(
    "metadata",
    [
        {"connection": "unknown", "wallpaper_categories": ["space/nebulae"]},
        {"connection": "esaHubble", "wallpaper_categories": "space/nebulae"},
        {"connection": "esaWebb", "wallpaper_categories": ["nature/mountains"]},
        {
            "connection": "wikimediaCommons",
            "wallpaper_categories": ["nature/mountains"],
        },
        {
            "connection": "wikimediaCommons",
            "metadata": {"Categories": {"value": ["Featured mountain photographs"]}},
        },
    ],
)
def test_untrusted_or_unsupported_sidecar_mappings_are_rejected(
    policy: Policy, metadata: object
) -> None:
    """Provider metadata cannot assign content outside reviewed collection routes."""
    candidate = policy.image("tagged-provider.jpg", metadata)
    assert policy.run("eligible", str(candidate)).returncode == 1


@pytest.mark.parametrize("prefix", ["wikimedia-commons-", "esa-hubble-", "esa-webb-"])
def test_filename_provider_cannot_be_overridden_by_sidecar(
    policy: Policy, prefix: str
) -> None:
    """A conflicting provider claim does not bypass the filename provenance gate."""
    candidate = policy.image(
        prefix + "spoofed.jpg",
        {
            "connection": "esaHubble" if prefix != "esa-hubble-" else "esaWebb",
            "wallpaper_categories": ["space/nebulae"],
        },
    )
    assert policy.run("eligible", str(candidate)).returncode == 1


@pytest.mark.parametrize(
    "prefix", ["nasa-svs-", "nasa-image-library-", "cma-", "smithsonian-"]
)
def test_retired_archive_cache_stays_excluded_even_with_new_sidecar(
    policy: Policy, prefix: str
) -> None:
    """Old archive content cannot be revived by permissive personal settings."""
    candidate = policy.image(
        prefix + "document.jpg",
        {"connection": "esaWebb", "wallpaper_categories": ["space/nebulae"]},
    )
    assert policy.run("eligible", str(candidate)).returncode == 1


def test_personal_switch_leaves_geometry_to_chooser(policy: Policy) -> None:
    """Policy controls ownership preferences without duplicating image decoding."""
    candidate = policy.image("my square holiday photo.jpg")
    assert policy.run("eligible", str(candidate)).returncode == 0
    policy.command("personal", "off")
    assert policy.run("eligible", str(candidate)).returncode == 1
    policy.command("personal", "default")
    assert policy.run("eligible", str(candidate)).returncode == 0


def test_filter_preserves_null_delimited_paths_and_honors_preferences(
    policy: Policy,
) -> None:
    """Spaces and newlines in paths survive filtering without extra stdout text."""
    personal = policy.image("private\nphoto.jpg")
    approved = policy.image(
        "esa-hubble-approved photo.jpg",
        {"connection": "esaHubble", "wallpaper_categories": ["space/nebulae"]},
    )
    retired = policy.image("smithsonian-document.jpg")
    policy.command("personal", "off")
    incoming = (
        b"\0".join(os.fsencode(path) for path in (personal, approved, retired)) + b"\0"
    )
    result = policy.run("filter", "--null", stdin=incoming)
    assert result.returncode == 0, result.stderr.decode()
    assert result.stdout == os.fsencode(approved) + b"\0"


@pytest.mark.parametrize("target", ["nature", "nature/mountains"])
def test_category_default_restores_enable_without_erasing_source_choice(
    policy: Policy, target: str
) -> None:
    """Resetting an enable switch leaves separately chosen source overrides intact."""
    policy.command("category", target, "off")
    policy.command("source", "wikimediaCommons", target, "off")
    policy.command("category", target, "default")
    status = policy.command("status")
    node = status["settings"]["categories"]["nature"]
    if "/" in target:
        node = node["subcategories"]["mountains"]
    assert node["enable"] is True
    assert node["connections"]["wikimediaCommons"] is False
    assert "wikimediaCommons:nature/mountains" not in route_names(
        status["active_routes"]
    )


def test_cached_commons_honors_source_override_without_disabling_category(
    policy: Policy,
) -> None:
    """Source-specific exclusions affect old files, as well as future fetch plans."""
    candidate = policy.image(
        "wikimedia-commons-existing.jpg",
        {
            "metadata": {"Categories": {"value": "Featured mountain photographs"}},
        },
    )
    assert policy.run("eligible", str(candidate)).returncode == 0
    policy.command("source", "wikimediaCommons", "nature", "off")
    assert policy.run("eligible", str(candidate)).returncode == 1
    policy.command("source", "wikimediaCommons", "nature/mountains", "on")
    assert policy.run("eligible", str(candidate)).returncode == 0


@pytest.mark.parametrize(
    "extra_category",
    [
        "Featured montages",
        "Photographer/Animal photography",
        "Black and white photographs",
        "Historical documents",
    ],
)
def test_cached_photos_obey_acquisition_quality(
    policy: Policy, extra_category: str
) -> None:
    """Legacy downloads cannot bypass the current archive and artwork exclusions."""
    catalog = json.loads(
        (ROOT / "modules/home/desktop/wallpaper-catalog.json").read_text(
            encoding="utf-8"
        )
    )
    policy.write("catalog.json", catalog)
    path = policy.image(
        "wikimedia-commons-legacy.jpg",
        {
            "metadata": {
                "Categories": {
                    "value": "Featured pictures of mountains|" + extra_category
                }
            }
        },
    )
    assert policy.run("eligible", str(path)).returncode == 1


def test_real_catalog_requires_aerial_intersection(policy: Policy) -> None:
    """A viewpoint alone cannot admit parking lots into natural landscapes."""
    catalog = json.loads(
        (ROOT / "modules/home/desktop/wallpaper-catalog.json").read_text(
            encoding="utf-8"
        )
    )
    policy.write("catalog.json", catalog)
    aerial = policy.image(
        "wikimedia-commons-drone.jpg",
        {
            "metadata": {
                "Categories": {
                    "value": "Featured pictures from unmanned aerial vehicles"
                }
            }
        },
    )
    assert policy.run("eligible", str(aerial)).returncode == 1
    landscape = policy.image(
        "wikimedia-commons-mountain.jpg",
        {
            "metadata": {
                "Categories": {
                    "value": "Featured pictures of mountains|Featured pictures from unmanned aerial vehicles"
                }
            }
        },
    )
    assert policy.run("eligible", str(landscape)).returncode == 0


def test_city_membership_cannot_bypass_disabled_city_category(policy: Policy) -> None:
    """A city with mountains does not re-enter the disabled city collection as nature."""
    catalog = json.loads(
        (ROOT / "modules/home/desktop/wallpaper-catalog.json").read_text(
            encoding="utf-8"
        )
    )
    policy.write("catalog.json", catalog)
    path = policy.image(
        "wikimedia-commons-town.jpg",
        {
            "metadata": {
                "Categories": {
                    "value": "Featured pictures of cityscapes|Featured pictures of mountains"
                }
            }
        },
    )
    assert policy.run("eligible", str(path)).returncode == 0
    policy.command("category", "cityscapes", "off")
    assert policy.run("eligible", str(path)).returncode == 1


@pytest.mark.parametrize("existing", [False, True])
def test_invalid_defaults_cannot_mutate_preferences(
    policy: Policy, existing: bool
) -> None:
    """Reject corrupt declarative settings before changing persistent overrides."""
    path = policy.root / "runtime/preferences.json"
    if existing:
        policy.command("personal", "off")
    before = path.read_bytes() if path.exists() else None
    policy.write("config.json", {"personal": "invalid"})
    result = policy.run("connection", "esaWebb", "off")
    assert result.returncode != 0
    assert (path.read_bytes() if path.exists() else None) == before


def test_filter_preserves_paths_split_across_chunks(policy: Policy) -> None:
    """NUL framing preserves arbitrary filename bytes and an unterminated tail."""
    raw = os.fsencode(policy.root) + b"/photo-\xff\n.jpg"
    padding = b"\0" * (64 * 1024 - len(raw) // 2)
    result = policy.run("filter", "--null", stdin=padding + raw + b"\0\0" + raw)
    assert result.returncode == 0, result.stderr
    assert result.stdout == (raw + b"\0") * 2


def test_large_filter_input_uses_bounded_memory(
    policy: Policy, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A large candidate stream does not become a complete in-memory inventory."""
    main = runpy.run_path(str(SCRIPT))["main"]
    incoming, outgoing = policy.root / "incoming", policy.root / "outgoing"
    retired = os.fsencode(policy.root / ("smithsonian-" + "x" * 180)) + b"\0"
    accepted = os.fsencode(policy.image("final photo.jpg"))
    with incoming.open("wb") as stream:
        for _ in range(50000):
            stream.write(retired)
        stream.write(accepted)
    with incoming.open("rb") as source, outgoing.open("wb") as sink:
        monkeypatch.setattr(sys, "stdin", SimpleNamespace(buffer=source))
        monkeypatch.setattr(sys, "stdout", SimpleNamespace(buffer=sink))
        tracemalloc.start()
        try:
            result = main([
                "--catalog",
                str(policy.root / "catalog.json"),
                "--config",
                str(policy.root / "config.json"),
                "--preferences",
                str(policy.root / "runtime/preferences.json"),
                "filter",
                "--null",
            ])
            _, peak = tracemalloc.get_traced_memory()
        finally:
            tracemalloc.stop()
    assert result == 0
    assert outgoing.read_bytes() == accepted + b"\0"
    assert peak < 4 * 1024 * 1024
