"""Exercise scoped deploy subprocess placement using disposable executables."""

import json
import os
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Fixed disposable subprocess fixture.
import sys
from pathlib import Path

name = Path(sys.argv[0]).name
if name == "queue":
    os.execvpe(sys.argv[1], sys.argv[1:], os.environ | {"FIXTURE_QUEUED": "1"})  # ruff: ignore[start-process-with-no-shell] - Explicit fixture queue.
elif name == "nix":
    with Path(os.environ["FIXTURE_NIX_LOG"]).open("a", encoding="utf-8") as log:
        log.write(
            json.dumps({
                "argv": sys.argv[1:],
                "queued": os.environ.get("FIXTURE_QUEUED") == "1",
            })
            + "\n"
        )
else:
    for arguments in (
        ["eval", "path:/nix/store/source#deploy", "--json"],
        [
            "copy",
            "--to",
            "ssh-ng://root@macbook",
            "--derivation",
            "/nix/store/profile.drv",
        ],
        [
            "build",
            "/nix/store/profile.drv",
            "--eval-store",
            "auto",
            "--store",
            "ssh-ng://root@macbook",
        ],
    ):
        subprocess.run(["nix", *arguments], check=True)  # ruff: ignore[subprocess-without-shell-equals-true, start-process-with-partial-path] - Intentionally test scoped PATH resolution.
