"""Merge managed appearance settings into Codex's writable TOML configuration."""

from __future__ import annotations

import json
import os
import stat
import sys
import tempfile
from collections.abc import MutableMapping
from pathlib import Path
from typing import TYPE_CHECKING, Any

import tomllib

if TYPE_CHECKING:
    from collections.abc import Mapping

import tomlkit
from tomlkit.container import OutOfOrderTableProxy
from tomlkit.items import InlineTable


def merge_settings(
    target: MutableMapping[str, Any], settings: Mapping[str, Any]
) -> None:
    """Update owned fields without rewriting unrelated tables or comments."""
    for key, value in settings.items():
        if isinstance(value, dict):
            existing = target.get(key)
            if isinstance(
                existing,
                (InlineTable, OutOfOrderTableProxy),
            ):
                # Adding child tables to these representations can serialize
                # invalid TOML or change the scope of later dotted keys.
                # Normalize this table only; other document comments survive.
                normalized = tomlkit.item(existing.unwrap())
                del target[key]
                target[key] = normalized
            elif not isinstance(existing, MutableMapping):
                target[key] = tomlkit.table()
            merge_settings(target[key], value)
        else:
            target[key] = value


def configure(path: Path, settings: Mapping[str, Any]) -> bool:
    """Atomically apply appearance settings.

    Returns:
        Whether the file changed.

    Raises:
        RuntimeError: Codex changed its config before replacement.

    """
    # Follow a writable symlink instead of replacing the link itself.
    path = path.resolve()
    original = path.read_bytes() if path.exists() else None
    mode = stat.S_IMODE(path.stat().st_mode) if original is not None else 0o600
    document = tomlkit.parse(original.decode("utf-8") if original is not None else "")
    merge_settings(document, settings)

    # Native font selection clears face metadata when selecting a family.
    # Remove only faces for the font families managed by this integration.
    for variant in ("appearanceDarkChromeTheme", "appearanceLightChromeTheme"):
        fonts = settings.get("desktop", {}).get(variant, {}).get("fonts", {})
        for family in ("ui", "code", "content"):
            if family in fonts:
                document["desktop"][variant]["fonts"].pop(f"{family}Face", None)

    result = tomlkit.dumps(document).encode("utf-8")
    # Validate before touching the original file, including unusual TOML forms.
    if tomllib.loads(result.decode("utf-8")) != document.unwrap():
        msg = "Appearance update changed TOML structure during serialization"
        raise RuntimeError(msg)
    if result == original:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(
        prefix=".codex-appearance-", dir=path.parent
    )
    try:
        with os.fdopen(descriptor, "wb") as output:
            output.write(result)
            output.flush()
            os.fchmod(output.fileno(), mode)
            os.fsync(output.fileno())
        current = path.read_bytes() if path.exists() else None
        if current != original:
            msg = "Codex configuration changed during the update; retry activation"
            raise RuntimeError(msg)
        Path(temporary).replace(path)
    finally:
        Path(temporary).unlink(missing_ok=True)
    return True


if __name__ == "__main__":
    configure(
        Path(sys.argv[1]), json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
    )
