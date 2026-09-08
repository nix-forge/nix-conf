"""Write the fallback Jujutsu identity without following a managed template link."""

from __future__ import annotations

import argparse
import json
import os
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Read Git identity through private pipes.
import sys
import tempfile
from pathlib import Path


def _toml_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False).replace("\x7f", "\\u007f")


def _write_identity(destination: Path, name: str, email: str) -> None:
    if not name or not email:
        destination.unlink(missing_ok=True)
        return
    destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    destination.parent.chmod(0o700)
    # Retain non-BMP Unicode and escape DEL, which JSON permits literally but
    # TOML basic strings prohibit. Values never enter child process arguments.
    content = f"[user]\nname = {_toml_string(name)}\nemail = {_toml_string(email)}\n"
    descriptor, temporary = tempfile.mkstemp(
        prefix=".identity-", dir=destination.parent
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            output.write(content)
        # mkstemp creates mode 0600. Replacing the directory entry also safely
        # handles a symlink into an old read-only or deleted nix-seal generation.
        Path(temporary).replace(destination)
    finally:
        Path(temporary).unlink(missing_ok=True)


def _git_identity(git: str, key: str) -> str:
    result = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Nix supplies Git; fixed argument vector.
        [git, "config", "--global", "--get", f"user.{key}"],
        check=False,
        capture_output=True,
        text=True,
        timeout=30,
    )
    if result.returncode == 1:
        return ""
    result.check_returncode()
    return result.stdout.removesuffix("\n")


def _main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--git", required=True)
    args = parser.parse_args()
    _write_identity(
        args.destination,
        _git_identity(args.git, "name"),
        _git_identity(args.git, "email"),
    )


if __name__ == "__main__":
    try:
        _main()
    except (OSError, UnicodeError, subprocess.SubprocessError):
        # Git diagnostics can include private identity data; never relay them.
        sys.stderr.write("Unable to install the private Jujutsu identity.\n")
        sys.exit(1)
