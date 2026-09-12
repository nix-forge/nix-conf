"""Shared wallpaper preferences, collection planning and cached-image admission."""

# ruff: file-ignore[print, raise-vanilla-args, raw-string-in-exception, f-string-in-exception]
# This operator CLI reports actionable diagnostics directly to its caller.
from __future__ import annotations

import argparse
import fcntl
import json
import os
import re
import sys
import tempfile
from pathlib import Path
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from collections.abc import Iterator, Sequence
    from typing import BinaryIO

Json = dict[str, Any]
CATEGORY_DEPTH = 2


def _read_object(path: Path) -> Json:
    """Reject corrupt settings instead of silently enabling disabled content.

    Returns:
        The parsed object.

    Raises:
        TypeError: The file contains a JSON value other than an object.

    """
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise TypeError(f"Expected a JSON object in {path}")
    return value


def _merge(base: Json, overrides: Json) -> Json:
    """Overlay runtime choices onto the declarative defaults.

    Returns:
        A new merged settings object.

    """
    result = base.copy()
    for key, value in overrides.items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = _merge(result[key], value)
        else:
            result[key] = value
    return result


def _switches(values: Json, names: Json, *, nullable: bool = False) -> None:
    if not isinstance(values, dict) or set(values) - set(names):
        raise ValueError("Unknown wallpaper connection or category")
    if any(
        type(v) is not bool and not (nullable and v is None) for v in values.values()
    ):
        raise ValueError("Wallpaper switches must be true or false")


def _node(value: Json, catalog: Json, leaves: Json | None = None) -> None:
    if not isinstance(value, dict) or set(value) - {
        "enable",
        "connections",
        "subcategories",
    }:
        raise ValueError("Invalid wallpaper category settings")
    if "enable" in value and type(value["enable"]) is not bool:
        raise ValueError("Category enable must be true or false")
    _switches(value.get("connections", {}), catalog["connections"], nullable=True)
    children = value.get("subcategories", {})
    if not isinstance(children, dict) or set(children) - set(leaves or {}):
        raise ValueError("Unknown wallpaper subcategory")
    for child in children.values():
        _node(child, catalog)


def _validate(settings: Json, catalog: Json) -> None:
    """Check persisted settings, including names and strict boolean types.

    Raises:
        ValueError: A setting or category identifier is invalid.

    """
    if set(settings) - {"connections", "categories", "personal"}:
        raise ValueError("Unknown wallpaper settings")
    _switches(settings.get("connections", {}), catalog["connections"])
    if "personal" in settings and type(settings["personal"]) is not bool:
        raise ValueError("Personal wallpapers switch must be true or false")
    categories = settings.get("categories", {})
    if not isinstance(categories, dict) or set(categories) - set(catalog["categories"]):
        raise ValueError("Unknown wallpaper category")
    for name, value in categories.items():
        _node(value, catalog, catalog["categories"][name]["subcategories"])


def _allowed(settings: Json, connection: str, category: str, subcategory: str) -> bool:
    """Apply global gates first, then the nearest explicit source override.

    Returns:
        Whether this supported category/source combination is enabled.

    """
    if not settings.get("connections", {}).get(connection, False):
        return False
    parent = settings.get("categories", {}).get(category, {})
    child = parent.get("subcategories", {}).get(subcategory, {})
    if not parent.get("enable", True) or not child.get("enable", True):
        return False
    for scope in (child, parent):
        override = scope.get("connections", {}).get(connection)
        if override is not None:
            return override
    return True


def _plan(settings: Json, catalog: Json, connection: str | None = None) -> list[Json]:
    """Return only supported, enabled routes; adapters cannot invent sources.

    Returns:
        The eligible catalog routes.

    """
    return [
        route
        for route in catalog["routes"]
        if (connection is None or route["connection"] == connection)
        and _allowed(
            settings, route["connection"], route["category"], route["subcategory"]
        )
    ]


def _assignments(metadata: Json, catalog: Json, connection: str) -> list[str]:
    """Classify source metadata using reviewed collection membership.

    Returns:
        All matching category/subcategory identifiers.

    """
    categories = metadata.get("metadata", {}).get("Categories", {}).get("value", "")
    if not isinstance(categories, str):
        return []
    quality = catalog.get("commonsQuality", {})
    raw_metadata = metadata.get("metadata", {})
    subject = " ".join(
        value
        for value in [
            metadata.get("title"),
            raw_metadata.get("ImageDescription", {}).get("value"),
            categories,
        ]
        if isinstance(value, str)
    )
    if quality and (
        re.search(quality["rejectedSubjects"], subject, re.IGNORECASE)
        or any(
            re.search(quality["rejectedCategories"], value, re.IGNORECASE)
            for value in categories.replace("_", " ").split("|")
        )
    ):
        return []
    collections = categories.replace("_", " ").split("|")
    return sorted({
        route["category"] + "/" + route["subcategory"]
        for route in catalog["routes"]
        if route["connection"] == connection
        and route.get("collection") in collections
        and all(item in collections for item in route.get("requireCollections", []))
        and not any(item in collections for item in route.get("excludeCollections", []))
    })


def _eligible(
    path: Path, settings: Json, catalog: Json, supported: dict[str, set[str]]
) -> bool:
    """Recheck cached provenance against current preferences on every rotation.

    Returns:
        Whether the file belongs to an enabled source and category.

    """
    # Retired archive feeds stay excluded even when their old files remain.
    if path.name.startswith((
        "nasa-svs-",
        "nasa-image-library-",
        "cma-",
        "smithsonian-",
    )):
        return False
    known = {
        "wikimedia-commons-": "wikimediaCommons",
        "esa-hubble-": "esaHubble",
        "esa-webb-": "esaWebb",
    }
    inferred = next(
        (source for prefix, source in known.items() if path.name.startswith(prefix)),
        None,
    )
    sidecar = Path(str(path) + ".json")
    if not sidecar.exists():
        return inferred is None and settings.get("personal", True)
    try:
        metadata = _read_object(sidecar)
        connection = metadata.get("connection", inferred)
        if connection is None:
            return inferred is None and settings.get("personal", True)
        if connection not in catalog["connections"] or (
            inferred and inferred != connection
        ):
            return False
        # Old Commons files already carry full source category metadata.
        # Derive their taxonomy without modifying or trusting a filename title.
        groups = (
            _assignments(metadata, catalog, connection)
            if connection == "wikimediaCommons"
            else metadata.get("wallpaper_categories", [])
        )
        return isinstance(groups, list) and any(
            isinstance(group, str) and group in supported.get(connection, ())
            for group in groups
        )
    except (OSError, ValueError, TypeError, AttributeError):
        return False


def _change(overrides: Json, args: argparse.Namespace, catalog: Json) -> None:
    """Edit one explicit preference, keeping all other choices intact.

    Raises:
        ValueError: A setting or category identifier is invalid.

    """
    command, target, setting = args.command, args.target, args.setting
    if command == "connection":
        if target not in catalog["connections"]:
            raise ValueError(f"Unknown connection: {target}")
        node = overrides.setdefault("connections", {})
        key = target
    elif command == "personal":
        node, key = overrides, "personal"
    else:
        parts = target.split("/")
        if len(parts) > CATEGORY_DEPTH or parts[0] not in catalog["categories"]:
            raise ValueError(f"Unknown category: {target}")
        if (
            len(parts) == CATEGORY_DEPTH
            and parts[1] not in catalog["categories"][parts[0]]["subcategories"]
        ):
            raise ValueError(f"Unknown subcategory: {target}")
        node = overrides.setdefault("categories", {}).setdefault(parts[0], {})
        if len(parts) == CATEGORY_DEPTH:
            node = node.setdefault("subcategories", {}).setdefault(parts[1], {})
        key = "enable"
        if command == "source":
            if args.connection not in catalog["connections"]:
                raise ValueError(f"Unknown connection: {args.connection}")
            node = node.setdefault("connections", {})
            key = args.connection
    if setting == "default":
        node.pop(key, None)
    else:
        node[key] = None if setting == "inherit" else setting == "on"


def _write_settings(path: Path, value: Json) -> None:
    """Publish preferences atomically so fetchers never read a partial file."""
    descriptor, temporary = tempfile.mkstemp(prefix=".preferences-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            json.dump(value, stream, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        Path(temporary).replace(path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def _parser() -> argparse.ArgumentParser:
    """Define the operator and internal adapter commands.

    Returns:
        The configured argument parser.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, required=True)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--preferences", type=Path, required=True)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("status")
    route_parser = commands.add_parser("plan")
    route_parser.add_argument("connection", nargs="?")
    check = commands.add_parser("eligible")
    check.add_argument("path", type=Path)
    check_many = commands.add_parser("filter")
    check_many.add_argument("--null", action="store_true", required=True)
    for command in ("connection", "category", "source", "personal"):
        sub = commands.add_parser(command)
        if command == "source":
            sub.add_argument("connection")
        if command != "personal":
            sub.add_argument("target")
        else:
            sub.set_defaults(target="personal")
        choices = ["on", "off", "default"] + (
            ["inherit"] if command == "source" else []
        )
        sub.add_argument("setting", choices=choices)
    return parser


def _null_paths(stream: BinaryIO) -> Iterator[bytes]:
    """Yield NUL-separated filenames without retaining the complete input.

    Yields:
        Nonempty records, including an unterminated final filename.

    """
    pending = b""
    while chunk := stream.read(64 * 1024):
        records = (pending + chunk).split(b"\0")
        pending = records.pop()
        yield from (record for record in records if record)
    if pending:
        yield pending


def _execute(args: argparse.Namespace) -> int:
    catalog = _read_object(args.catalog)
    defaults = _read_object(args.config)
    # Reject invalid declarative input before a mutating command saves overrides.
    _validate(defaults, catalog)
    preferences = args.preferences
    if args.command in {"connection", "category", "source", "personal"}:
        preferences.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        with preferences.with_suffix(".lock").open("w", encoding="utf-8") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            overrides = _read_object(preferences) if preferences.exists() else {}
            _validate(overrides, catalog)
            _change(overrides, args, catalog)
            _validate(overrides, catalog)
            _write_settings(preferences, overrides)
    overrides = _read_object(preferences) if preferences.exists() else {}
    _validate(overrides, catalog)
    settings = _merge(defaults, overrides)
    supported: dict[str, set[str]] = {}
    if args.command in {"eligible", "filter"}:
        # These settings are fixed for this invocation. Reuse its route index
        # across files without caching mutable preferences between commands.
        for route in _plan(settings, catalog):
            supported.setdefault(route["connection"], set()).add(
                route["category"] + "/" + route["subcategory"]
            )
    if args.command == "eligible":
        return 0 if _eligible(args.path, settings, catalog, supported) else 1
    if args.command == "filter":
        for raw in _null_paths(sys.stdin.buffer):
            if _eligible(Path(os.fsdecode(raw)), settings, catalog, supported):
                sys.stdout.buffer.write(raw + b"\0")
    elif args.command == "plan":
        if (
            args.connection is not None
            and args.connection not in catalog["connections"]
        ):
            raise ValueError(f"Unknown connection: {args.connection}")
        print(json.dumps(_plan(settings, catalog, args.connection)))
    else:
        print(
            json.dumps(
                {
                    "settings": settings,
                    "active_routes": _plan(settings, catalog),
                    "catalog": catalog,
                },
                indent=2,
            )
        )
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    """Run a wallpaper command.

    Returns:
        Zero on success, one for an ineligible image, or 65 for invalid settings.

    """
    args = _parser().parse_args(argv)
    try:
        return _execute(args)
    except (OSError, ValueError, TypeError, KeyError) as error:
        print(f"Wallpaper preferences: {error}", file=sys.stderr)
        return 65


if __name__ == "__main__":
    sys.exit(main())
