"""Reveal a sealed bundle using private temporary files on the SSH host."""

import base64
import json
import subprocess
import sys
import tempfile
from pathlib import Path

request = json.load(sys.stdin)
with tempfile.TemporaryDirectory(prefix="identity-reveal-") as temporary:
    root = Path(temporary)
    source = Path(request["source"])
    if source.is_absolute() or ".." in source.parts:
        sys.exit(1)
    target = root / source
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(base64.b64decode(request["ciphertext"], validate=True))
    plan = root / "plan.json"
    plan.write_text(json.dumps(request["plan"]), encoding="utf-8")
    result = subprocess.run(
        [
            "nix-seal",
            "secret",
            "reveal",
            "--plan",
            str(plan),
            "--repository-root",
            str(root),
            "--secret",
            request["secret"],
            "--identity",
            request["identity"],
        ],
        check=False,
        text=True,
        capture_output=True,
    )
    if result.returncode:
        sys.exit(1)
    sys.stdout.write(result.stdout)
