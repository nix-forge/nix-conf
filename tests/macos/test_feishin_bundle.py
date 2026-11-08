"""Check Feishin's private player bundle with bundled and executable-only mpv."""

from __future__ import annotations

import os
import plistlib
import shlex
import shutil
import subprocess  # ruff: ignore[suspicious-subprocess-import]
from pathlib import Path

import pytest

ASSETS = Path(__file__).resolve().parents[2] / "modules/home/feishin-assets"


@pytest.mark.parametrize("bundled", [False, True])
def test_player_bundle(tmp_path: Path, bundled: bool) -> None:
    """Both supported package shapes retain the player and Feishin identity."""
    bash = shutil.which("bash")
    signing_stub = shutil.which("true")
    assert bash is not None
    assert signing_stub is not None
    player = tmp_path / "custom player"
    executable = player / "bin/mpv"
    executable.parent.mkdir(parents=True)
    executable.write_text(f"#!{bash}\nprintf 'player-ok\\n'\n")
    executable.chmod(0o755)
    if bundled:
        contents = player / "Applications/mpv.app/Contents"
        (contents / "MacOS").mkdir(parents=True)
        (contents / "Resources").mkdir()
        (contents / "MacOS/mpv").write_bytes(executable.read_bytes())
        (contents / "MacOS/mpv").chmod(0o755)
        (contents / "Info.plist").write_bytes(
            plistlib.dumps({
                "CFBundleExecutable": "mpv",
                "CFBundlePackageType": "APPL",
                "CFBundleURLTypes": [{"CFBundleURLSchemes": ["mpv"]}],
            })
        )
    feishin = tmp_path / "feishin"
    icon = feishin / "Applications/Feishin.app/Contents/Resources/icon.icns"
    icon.parent.mkdir(parents=True)
    icon.write_bytes(b"fixture-icon")
    values = {
        "config_programs_mpv_finalPackage_unwrapped": player,
        "lib_escapeShellArg_mpvBinary": executable,
        "pkgs_feishin": feishin,
        "scripts_feishin_check_py": ASSETS / "configure_mpv_bundle.py",
        "lib_getExe_pkgs_rcodesign": signing_stub,
    }
    script = (ASSETS / "build-mpv-bundle.sh").read_text()
    for name, value in values.items():
        script = script.replace(f"@{name}@", shlex.quote(str(value)))
    output = tmp_path / "output"
    environment = os.environ | {"out": str(output)}
    subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Repository source and quoted fixture paths.
        [bash, "-euc", "runHook() { :; };\n" + script],
        env=environment,
        check=True,
    )
    contents = output / "Applications/Feishin mpv.app/Contents"
    info = plistlib.loads((contents / "Info.plist").read_bytes())
    assert info["CFBundleExecutable"] == "mpv"
    assert info["CFBundleIdentifier"] == "org.jeffvli.feishin.mpv"
    assert "CFBundleURLTypes" not in info
    assert (contents / "Resources/icon.icns").read_bytes() == b"fixture-icon"
    result = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Locally generated fixture executable.
        [str(contents / "MacOS/mpv")], check=True, capture_output=True, text=True
    )
    assert result.stdout == "player-ok\n"
