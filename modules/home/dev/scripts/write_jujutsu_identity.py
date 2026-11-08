"""Write the fallback Jujutsu identity without following a managed template link."""

from __future__ import annotations

import argparse
import json
import os
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Read Git identity through private pipes.
import sys
import tempfile
import tomllib
from pathlib import Path

from notification_process import run as run_command


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
    result = run_command(
        [git, "config", "--global", "--includes", "--get", f"user.{key}"],
        check=False,
        capture_output=True,
        text=True,
        timeout=30,
    )
    if result.returncode == 1:
        return ""
    result.check_returncode()
    return result.stdout.removesuffix("\n")


def _link_identity(destination: Path, source: Path) -> None:
    resolved = source.resolve(strict=True)
    info = resolved.stat()
    if (
        not resolved.is_file()
        or resolved.is_relative_to("/nix/store")
        or info.st_uid not in {0, os.getuid()}
        or info.st_mode & 0o077
    ):
        message = "Identity source must be a protected runtime file"
        raise ValueError(message)
    identity = tomllib.loads(resolved.read_text(encoding="utf-8"))
    user = identity.get("user", {})
    if (
        set(identity) != {"user"}
        or not isinstance(user, dict)
        or set(user) != {"name", "email"}
        or any(not isinstance(user[key], str) or not user[key] for key in user)
    ):
        message = "Identity source must contain only a nonempty name and email"
        raise ValueError(message)
    destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    destination.parent.chmod(0o700)
    with tempfile.TemporaryDirectory(
        prefix=".identity-", dir=destination.parent
    ) as directory:
        link = Path(directory) / "identity"
        link.symlink_to(source)
        link.replace(destination)


def _main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--git")
    mode.add_argument("--source", type=Path)
    args = parser.parse_args()
    if args.source is not None:
        _link_identity(args.destination, args.source)
    else:
        _write_identity(
            args.destination,
            _git_identity(args.git, "name"),
            _git_identity(args.git, "email"),
        )


if __name__ == "__main__":
    try:
        _main()
    except OSError, UnicodeError, ValueError, subprocess.SubprocessError:
        # Git diagnostics can include private identity data; never relay them.
        sys.stderr.write("Unable to install the private Jujutsu identity.\n")
        sys.exit(1)
