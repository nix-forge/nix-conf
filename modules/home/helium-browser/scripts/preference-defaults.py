"""Apply Nix-managed defaults to Helium's Chromium preference file."""

import json
import os
import pathlib
import tempfile

preferences_path = (
    pathlib.Path.home()
    / "Library/Application Support/net.imput.helium/Default/Preferences"
)
applied_version = 5

try:
    preferences = json.loads(preferences_path.read_text())
except (FileNotFoundError, json.JSONDecodeError):
    preferences = {}

helium_preferences = preferences.setdefault("helium", {})
if helium_preferences.get("nix_default_preferences_version", 0) < applied_version:
    browser_preferences = helium_preferences.setdefault("browser", {})
    browser_preferences.update({
        "layout": 2,
        "rounded_frame": True,
        "zen_mode": True,
    })
    helium_preferences.setdefault("settings", {}).setdefault("a11y", {})[
        "copy_page_url_shortcut"
    ] = True
    helium_preferences["settings"].setdefault("behavior", {})[
        "vertical_collapse_shortcut"
    ] = True
    preferences.setdefault("ntp", {}).update({
        "personal_shortcuts_visible": False,
        "enterprise_shortcuts_visible": False,
    })
    browser_preferences.setdefault("custom_accelerators", {})["34090"] = {
        "added": ["Alt+Meta+KeyS"],
        "removed": ["Meta+KeyS"],
    }
    extension_commands = preferences.setdefault("extensions", {}).setdefault(
        "commands", {}
    )
    extension_commands.pop("mac:Command+Shift+L", None)
    extension_commands["mac:Command+Alt+Shift+L"] = {
        "command_name": "autofill_login",
        "extension": "nngceckbapebfimnlniiiahkandclblb",
        "global": False,
    }
    helium_preferences["nix_default_preferences_version"] = applied_version

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
