"""Check declarative preference seeding and the sourced browser launch hook."""

import json
import shlex
import shutil
import sys
from pathlib import Path

from notification_process import run

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "modules/home/browsers/helium/scripts"


def test_declared_preferences_preserve_ui_changes_until_configuration_changes(
    tmp_path: Path,
) -> None:
    """Only changed declarations reseed managed leaves; other settings survive."""
    defaults = tmp_path / "defaults.json"
    preferences = tmp_path / "custom profile %literal$dollar/Preferences"
    preferences.parent.mkdir()
    preferences.write_text(
        json.dumps({
            "unmanaged": {"keep": True},
            "obsolete": {"remove": True, "keep": True},
        })
    )
    defaults.write_text(
        json.dumps({
            "values": {"helium": {"browser": {"layout": 2}}},
            "remove": [["obsolete", "remove"]],
        })
    )
    command = [
        sys.executable,
        str(ASSETS / "preference_defaults.py"),
        str(defaults),
        str(preferences),
    ]
    run(command, check=True, timeout=5)
    seeded = json.loads(preferences.read_text())
    assert seeded["unmanaged"] == {"keep": True}
    assert "extensions" not in seeded
    assert seeded["obsolete"] == {"keep": True}
    seeded["helium"]["browser"]["layout"] = 99
    preferences.write_text(json.dumps(seeded))
    before = preferences.read_bytes()
    run(command, check=True, timeout=5)
    assert preferences.read_bytes() == before
    next_layout = 3
    defaults.write_text(
        json.dumps({
            "values": {"helium": {"browser": {"layout": next_layout}}},
            "remove": [],
        })
    )
    run(command, check=True, timeout=5)
    updated = json.loads(preferences.read_text())
    assert updated["helium"]["browser"]["layout"] == next_layout
    assert updated["unmanaged"] == {"keep": True}
    assert not list(preferences.parent.glob("Preferences.nix-*"))


def test_sourced_preference_hook_returns_to_the_browser_launcher(
    tmp_path: Path,
) -> None:
    """A successful defaults helper must not replace its sourcing launcher."""
    defaults = tmp_path / "defaults.json"
    defaults.write_text('{"values": {}, "remove": []}')
    preferences = tmp_path / "profile/Preferences"
    helper = tmp_path / "defaults-helper"
    bash = shutil.which("bash")
    assert bash is not None
    helper.write_text(
        (Path(__file__).with_name("fixtures") / "helium-helper.sh.in")
        .read_text()
        .replace("@bash@", bash)
        .replace("@python@", shlex.quote(sys.executable))
        .replace("@source@", shlex.quote(str(ASSETS / "preference_defaults.py")))
    )
    helper.chmod(0o700)
    hook = tmp_path / "apply-preference-defaults.sh"
    hook.write_text(
        (ASSETS / "apply-preference-defaults.sh")
        .read_text()
        .replace("@bash@", bash)
        .replace("@defaults@", shlex.quote(str(helper)))
        .replace("@defaultsFile@", shlex.quote(str(defaults)))
        .replace("@preferencesPath@", shlex.quote(str(preferences)))
    )
    launcher = tmp_path / "launch.sh"
    launcher.write_text(
        (Path(__file__).with_name("fixtures") / "helium-launch.sh.in")
        .read_text()
        .replace("@hook@", shlex.quote(str(hook)))
    )
    result = run(
        ["bash", str(launcher)], capture_output=True, text=True, check=True, timeout=5
    )
    assert result.stdout == "extension-hook\nbrowser-launch\n"
    assert preferences.exists()
