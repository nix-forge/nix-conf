"""Point every Gecko installation ID at Home Manager's default profile."""

from __future__ import annotations

import argparse
import os
import stat
import sys
import tempfile
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Sequence


def _parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profiles-registry", required=True, type=Path)
    parser.add_argument("--install-registry", required=True, type=Path)
    parser.add_argument("--default-profile", required=True)
    return parser.parse_args(list(argv))


def _fail(message: str) -> int:
    sys.stderr.write(f"error: {message}\n")
    return 1


def _registered_profiles(path: Path) -> set[str]:
    content = path.read_text(encoding="utf-8")
    return {
        line.removeprefix("Path=")
        for line in content.splitlines()
        if line.startswith("Path=")
    }


def _updated_registry(content: str, default_profile: str) -> tuple[str, int]:
    replacements = 0
    updated_lines: list[str] = []
    for line in content.splitlines(keepends=True):
        updated_line = line
        if line.startswith("Default="):
            if line.endswith("\r\n"):
                line_ending = "\r\n"
            elif line.endswith("\n"):
                line_ending = "\n"
            else:
                line_ending = ""
            profile_value = line.removeprefix("Default=")
            current_profile = profile_value.removesuffix(line_ending)
            if current_profile != default_profile:
                updated_line = f"Default={default_profile}{line_ending}"
                replacements += 1
        updated_lines.append(updated_line)
    return "".join(updated_lines), replacements


def _write_atomic(path: Path, content: str, mode: int) -> None:
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.",
        dir=path.parent,
    )
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(
            descriptor,
            "w",
            encoding="utf-8",
            newline="",
        ) as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        temporary_path.chmod(mode)
        temporary_path.replace(path)
    finally:
        temporary_path.unlink(missing_ok=True)


def _reconcile(args: argparse.Namespace) -> str:
    default_profile = args.default_profile
    if (
        not default_profile.startswith("Profiles/")
        or "\n" in default_profile
        or "\r" in default_profile
        or ".." in Path(default_profile).parts
    ):
        msg = f"invalid relative profile path: {default_profile!r}"
        raise ValueError(msg)

    registered_profiles = _registered_profiles(args.profiles_registry)
    if default_profile not in registered_profiles:
        msg = (
            f"default profile {default_profile!r} is absent from "
            f"{args.profiles_registry}"
        )
        raise ValueError(msg)

    try:
        registry_stat = args.install_registry.lstat()
    except FileNotFoundError:
        return "install registry does not exist yet"

    if not stat.S_ISREG(registry_stat.st_mode):
        registry = args.install_registry
        msg = f"install registry is not a regular file: {registry}"
        raise ValueError(msg)

    old_content = args.install_registry.read_text(encoding="utf-8")
    new_content, replacements = _updated_registry(old_content, default_profile)
    if replacements == 0:
        return "install registry is already current"

    _write_atomic(
        args.install_registry,
        new_content,
        stat.S_IMODE(registry_stat.st_mode),
    )
    return f"reconciled {replacements} stale install mappings"


def _main(argv: Sequence[str] | None = None) -> int:
    args = _parse_args(argv if argv is not None else sys.argv[1:])
    try:
        message = _reconcile(args)
    except (OSError, ValueError) as error:
        return _fail(str(error))
    sys.stdout.write(f"{message}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
