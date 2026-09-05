"""Print a stable hash of the user-visible macOS Dock layout."""

from __future__ import annotations

import hashlib
import json
import os
import plistlib
import subprocess as sp  # ruff:ignore[suspicious-subprocess-import]
import sys
from typing import cast

_DEFAULTS_OVERRIDE = "DOCK_DEFAULTS_BIN_OVERRIDE"
_DEFAULTS_BIN = "/usr/bin/defaults"


def _export_dock() -> dict[str, object]:
    defaults_bin = os.environ.get(_DEFAULTS_OVERRIDE, _DEFAULTS_BIN)
    # This same-user test adapter never crosses a privilege boundary.
    result = sp.run(  # ruff: ignore[subprocess-without-shell-equals-true]
        [defaults_bin, "export", "com.apple.dock", "-"],
        check=True,
        capture_output=True,
    )
    loaded = plistlib.loads(result.stdout)
    if not isinstance(loaded, dict):
        msg = "The exported Dock preferences are not a dictionary."
        raise TypeError(msg)
    return cast("dict[str, object]", loaded)


def _normalize_tile(tile: object) -> dict[str, object]:
    if not isinstance(tile, dict):
        return {"tile-type": "invalid"}

    tile_values = cast("dict[str, object]", tile)
    tile_data = tile_values.get("tile-data")
    if not isinstance(tile_data, dict):
        tile_data = {}

    tile_data_values = cast("dict[str, object]", tile_data)
    file_data = tile_data_values.get("file-data")
    if not isinstance(file_data, dict):
        file_data = {}

    file_data_values = cast("dict[str, object]", file_data)
    return {
        "tile-type": tile_values.get("tile-type"),
        "url": file_data_values.get("_CFURLString"),
        "arrangement": tile_data_values.get("arrangement"),
        "displayas": tile_data_values.get("displayas"),
        "showas": tile_data_values.get("showas"),
    }


def _normalized_layout(
    plist: dict[str, object],
) -> dict[str, list[dict[str, object]]]:
    result: dict[str, list[dict[str, object]]] = {}
    for section in ("persistent-apps", "persistent-others"):
        tiles = plist.get(section, [])
        if not isinstance(tiles, list):
            tiles = []
        result[section] = [_normalize_tile(tile) for tile in tiles]
    return result


def main() -> int:
    """Hash the Dock fields managed by the Home Manager module.

    Returns:
        Zero on success, or one when the Dock preferences cannot be read.

    """
    try:
        encoded = json.dumps(
            _normalized_layout(_export_dock()),
            ensure_ascii=True,
            separators=(",", ":"),
            sort_keys=True,
        ).encode()
    except (
        OSError,
        plistlib.InvalidFileException,
        sp.SubprocessError,
        TypeError,
    ) as error:
        sys.stderr.write(f"Unable to read the current Dock layout: {error}\n")
        return 1

    sys.stdout.write(f"{hashlib.sha256(encoded).hexdigest()}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
