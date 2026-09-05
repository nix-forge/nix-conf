"""Render secret Windows installer inputs without exposing them to Nix."""

from __future__ import annotations

import argparse
import os
import re
import stat
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path
from xml.sax.saxutils import escape

SECRET_PLACEHOLDER = "__WINDOWS_ADMINISTRATOR_PASSWORD_XML__"
MINIMUM_PASSWORD_LENGTH = 16
MINIMUM_PASSWORD_CATEGORIES = 3
EXPECTED_PLACEHOLDER_COUNT = 2
MINIMUM_PRINTABLE_ASCII = 0x21
MAXIMUM_PRINTABLE_ASCII = 0x7E


class SeedRenderError(ValueError):
    """Report a rejected secret input or malformed immutable template."""


def _reject(message: str) -> None:
    raise SeedRenderError(message)


def read_password(path: Path) -> str:
    """Read and validate the root-owned, single-line installer credential.

    Returns:
        The validated credential without its one permitted trailing newline.

    """
    metadata = path.lstat()
    if not stat.S_ISREG(metadata.st_mode) or path.is_symlink():
        _reject("password input must be a regular file, not a symlink")
    if metadata.st_mode & 0o077:
        _reject("password input must not be accessible by group or other users")

    password = path.read_text(encoding="utf-8")
    password = password.removesuffix("\n")
    if "\n" in password or "\r" in password:
        _reject("password input must contain exactly one line")
    if len(password) < MINIMUM_PASSWORD_LENGTH:
        _reject("password must contain at least 16 characters")
    if re.match(r"[A-Za-z0-9]", password) is None:
        _reject("password must begin with a letter or digit")
    if any(character.isspace() for character in password):
        _reject("password must not contain whitespace")
    if not password.isascii() or any(
        not MINIMUM_PRINTABLE_ASCII <= ord(character) <= MAXIMUM_PRINTABLE_ASCII
        for character in password
    ):
        _reject("password must contain printable ASCII characters only")
    categories = sum(
        bool(re.search(pattern, password))
        for pattern in (r"[a-z]", r"[A-Z]", r"[0-9]", r"[^A-Za-z0-9]")
    )
    if categories < MINIMUM_PASSWORD_CATEGORIES:
        _reject("password must use at least three character categories")
    return password


def _write_descriptor(descriptor: int, content: bytes, mode: int) -> None:
    try:
        os.fchmod(descriptor, mode)
    except BaseException:
        os.close(descriptor)
        raise
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(content)
        stream.flush()
        os.fsync(stream.fileno())


def atomic_write(path: Path, content: bytes, mode: int) -> None:
    """Atomically replace one fixed output with explicitly restricted permissions."""
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", dir=path.parent
    )
    temporary = Path(temporary_name)
    try:
        _write_descriptor(descriptor, content, mode)
        temporary.replace(path)
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise


def render(
    template: Path, answer_file: Path, credential_file: Path, password_file: Path
) -> None:
    """Render the answer file and guest-local credential into fixed private outputs."""
    password = read_password(password_file)
    source = template.read_text(encoding="utf-8")
    occurrences = source.count(SECRET_PLACEHOLDER)
    if occurrences != EXPECTED_PLACEHOLDER_COUNT:
        _reject(
            f"answer template must contain the password token twice, found {occurrences}"
        )

    rendered = source.replace(SECRET_PLACEHOLDER, escape(password))
    # The template is immutable Nix store data, and the only variable text was
    # XML-escaped above. No untrusted document or entity declaration is parsed.
    ET.fromstring(rendered)
    atomic_write(answer_file, rendered.encode("utf-8"), 0o600)
    atomic_write(credential_file, f"{password}\n".encode(), 0o600)


def main() -> None:
    """Validate command-line paths and render the volatile installer seed inputs."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--template", type=Path, required=True)
    parser.add_argument("--answer-file", type=Path, required=True)
    parser.add_argument("--credential-file", type=Path, required=True)
    parser.add_argument("--password-file", type=Path, required=True)
    arguments = parser.parse_args()
    render(
        arguments.template,
        arguments.answer_file,
        arguments.credential_file,
        arguments.password_file,
    )


if __name__ == "__main__":
    main()
