"""Sync Finder favorites from embedded Home Manager configuration."""

from __future__ import annotations

import json
import os
import subprocess  # noqa: S404
from pathlib import Path
from typing import Final, TypedDict

_DEFAULT_MYSIDES_BIN: Final[str] = "__DEFAULT_MYSIDES_BIN__"
_FAVORITES_JSON: Final[str] = "__FAVORITES_JSON__"
_MYSIDES_BIN_OVERRIDE: Final[str] = "MYSIDES_BIN_OVERRIDE"


class _FavoriteEntry(TypedDict):
    label: str
    path: str


def _parse_sidebar_line(line: str) -> tuple[str, str] | None:
    if " -> " not in line:
        return None

    label, uri = line.split(" -> ", 1)
    return label.strip(), _normalize_uri(uri.strip())


def _normalize_uri(uri: str) -> str:
    return uri[:-1] if uri.startswith("file://") and uri.endswith("/") else uri


def _mysides_bin() -> str:
    return os.environ.get(_MYSIDES_BIN_OVERRIDE, _DEFAULT_MYSIDES_BIN)


def _run_mysides(*args: str, check: bool) -> subprocess.CompletedProcess[str]:
    return subprocess.run(  # noqa: S603
        [_mysides_bin(), *args],
        check=check,
        capture_output=True,
        text=True,
    )


def _load_favorites() -> list[_FavoriteEntry]:
    loaded = json.loads(_FAVORITES_JSON)
    if not isinstance(loaded, list):
        msg = "Favorites payload must be a list."
        raise TypeError(msg)

    favorites: list[_FavoriteEntry] = []
    for item in loaded:
        if not isinstance(item, dict):
            msg = "Favorite entry must be an object."
            raise TypeError(msg)

        label = item.get("label")
        path = item.get("path")
        if not isinstance(label, str) or not isinstance(path, str):
            msg = "Favorite entry must contain string label and path values."
            raise TypeError(msg)

        favorites.append({"label": label, "path": path})

    return favorites


def _current_favorites() -> dict[str, str]:
    result = _run_mysides("list", check=False)
    favorites: dict[str, str] = {}

    for line in result.stdout.splitlines():
        parsed = _parse_sidebar_line(line)
        if parsed is None:
            continue

        label, uri = parsed
        favorites[label] = uri

    return favorites


def _sync_favorites() -> None:
    existing = _current_favorites()

    for entry in _load_favorites():
        path = Path(entry["path"])
        path.mkdir(parents=True, exist_ok=True)

        uri = _normalize_uri(path.as_uri())
        current_uri = existing.get(entry["label"])
        if current_uri == uri:
            continue

        if current_uri is not None:
            _run_mysides("remove", entry["label"], check=False)

        _run_mysides("add", entry["label"], uri, check=True)
        existing[entry["label"]] = uri


if __name__ == "__main__":
    _sync_favorites()
