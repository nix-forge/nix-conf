"""Atomically provision an IWD profile without publishing its SSID or credentials."""

from __future__ import annotations

import argparse
import os
import stat
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Native parser receives credentials through stdin only.
import sys
import tempfile
from pathlib import Path
from typing import TYPE_CHECKING

from notification_process import run as run_command

if TYPE_CHECKING:
    from collections.abc import Callable

SSID_MAX_BYTES = 32


def materialize(
    source: Path, directory: Path, profile_type: str, validator: Callable[[bytes], None]
) -> Path:
    """Copy a protected runtime profile using IWD's byte-based filename encoding.

    Returns:
        The private profile path.

    Raises:
        ValueError: The source is not a protected, well-formed runtime profile.

    """
    resolved = source.resolve(strict=True)
    info = resolved.stat()
    if (
        not stat.S_ISREG(info.st_mode)
        or resolved.is_relative_to("/nix/store")
        or info.st_uid != os.geteuid()
        or info.st_mode & 0o077
    ):
        message = (
            "The profile source must be private and owned by the provisioning user"
        )
        raise ValueError(message)
    header, separator, body = resolved.read_bytes().partition(b"\n")
    if not separator or not header.startswith(b"SSID="):
        message = "The profile requires an SSID header and native IWD configuration"
        raise ValueError(message)
    ssid = header.removesuffix(b"\r")[5:]
    if not 1 <= len(ssid) <= SSID_MAX_BYTES or b"\x00" in ssid:
        message = "The SSID must contain between one and 32 bytes"
        raise ValueError(message)
    ssid.decode("utf-8")
    allowed = b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _-"
    name = (
        ssid.decode("ascii")
        if all(byte in allowed for byte in ssid)
        else "=" + ssid.hex()
    )
    body.decode("utf-8")
    if b"\x00" in body:
        message = "The profile must not contain NUL bytes"
        raise ValueError(message)
    validator(body)
    if profile_type not in {"psk", "8021x", "open"}:
        message = (
            "The profile must contain native IWD sections and a supported network type"
        )
        raise ValueError(message)
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    if directory.stat().st_uid != os.geteuid():
        message = "The IWD state directory must belong to the provisioning user"
        raise ValueError(message)
    directory.chmod(0o700)
    destination = directory / f"{name}.{profile_type}"
    if (
        not destination.is_symlink()
        and destination.is_file()
        and destination.read_bytes() == body
    ):
        destination.chmod(0o600)
        return destination
    descriptor, temporary = tempfile.mkstemp(prefix=".iwd-profile-", dir=directory)
    try:
        with os.fdopen(descriptor, "wb") as output:
            output.write(body)
            output.flush()
            os.fsync(output.fileno())
        Path(temporary).replace(destination)
        descriptor = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
    finally:
        Path(temporary).unlink(missing_ok=True)
    return destination


def main() -> None:
    """Keep runtime data out of command diagnostics.

    Raises:
        SystemExit: The runtime profile could not be safely installed.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("directory", type=Path)
    parser.add_argument("validator", type=Path)
    parser.add_argument("profile_type", choices=["psk", "8021x", "open"])
    args = parser.parse_args()
    try:

        def validate(body: bytes) -> None:
            run_command(
                [str(args.validator)],
                input=body,
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )

        materialize(args.source, args.directory, args.profile_type, validate)
    except OSError, ValueError, UnicodeError, subprocess.SubprocessError:
        sys.stderr.write("Unable to install the protected IWD profile.\n")
        raise SystemExit(1) from None


if __name__ == "__main__":
    main()
