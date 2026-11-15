"""Apply Nix-managed defaults to Helium's Chromium preference file."""

import hashlib
import json
import os
import pathlib
import sys
import tempfile

policy = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
preferences_path = pathlib.Path(sys.argv[2])
defaults = policy["values"]
revision = hashlib.sha256(json.dumps(policy, sort_keys=True).encode()).hexdigest()


def merge_defaults(target: dict, source: dict) -> None:
    """Apply declared leaves while retaining unrelated application settings."""
    for key, value in source.items():
        if isinstance(value, dict):
            if not isinstance(target.get(key), dict):
                target[key] = {}
            merge_defaults(target[key], value)
        else:
            target[key] = value


try:
    preferences = json.loads(preferences_path.read_text(encoding="utf-8"))
except FileNotFoundError, json.JSONDecodeError:
    preferences = {}

helium_preferences = preferences.setdefault("helium", {})
if helium_preferences.get("nix_default_preferences_hash") != revision:
    merge_defaults(preferences, defaults)
    for key_path in policy["remove"]:
        parent = preferences
        for key in key_path[:-1]:
            if not isinstance(parent.get(key), dict):
                break
            parent = parent[key]
        else:
            parent.pop(key_path[-1], None)
    preferences.setdefault("helium", {})["nix_default_preferences_hash"] = revision

    preferences_path.parent.mkdir(parents=True, exist_ok=True)
    file_descriptor, temporary_path = tempfile.mkstemp(
        dir=preferences_path.parent,
        prefix="Preferences.nix-",
    )
    temporary_file_path = pathlib.Path(temporary_path)
    try:
        with os.fdopen(file_descriptor, "w") as temporary_file:
            json.dump(preferences, temporary_file, separators=(",", ":"))
            temporary_file.flush()
            os.fsync(temporary_file.fileno())
        temporary_file_path.replace(preferences_path)
    finally:
        if temporary_file_path.exists():
            temporary_file_path.unlink()
