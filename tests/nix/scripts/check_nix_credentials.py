"""Verify synthetic credential selection without printing credential settings."""

import json
import shutil
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Run only the fixed Nix inspection command.
import sys
from pathlib import Path

nix = shutil.which("nix")
assert nix is not None
result = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Execute the resolved Nix binary with fixed arguments.
    [nix, "--extra-experimental-features", "nix-command", "config", "show", "--json"],
    check=True,
    capture_output=True,
    text=True,
)
settings = json.loads(result.stdout)
assert settings["min-free"]["value"] == 214748364800
assert settings["max-free"]["value"] == 268435456000
kind = sys.argv[1]
if kind == "public":
    assert "/root-private/credentials.conf" not in Path(sys.argv[2]).read_text(
        encoding="utf-8"
    )
    assert not settings["access-tokens"]["value"]
else:
    assert settings["access-tokens"]["value"] == {
        "github.com": f"synthetic-{kind}-token"
    }
