"""Retire only the known boot bridge after declarative PKI takes ownership."""

import os
import stat
import sys
from pathlib import Path

ARGUMENT_COUNT = 3


def _owned_link(path: Path, target: str) -> bool:
    """Recognize one exact root-owned symlink without following it.

    Returns:
        Whether the link has the expected owner and literal target.

    """
    try:
        info = path.lstat()
    except FileNotFoundError:
        return False
    return (
        stat.S_ISLNK(info.st_mode)
        and info.st_uid == 0
        and str(path.readlink()) == target
    )


def _configured_trust(bundle: Path, trust_source: Path) -> bool:
    """Require all four aliases to belong to the declarative configuration.

    Returns:
        Whether normal activation installed the entire configured policy.

    """
    aliases = {
        "/etc/ssl/certs/ca-certificates.crt": bundle,
        "/etc/ssl/certs/ca-bundle.crt": bundle,
        "/etc/pki/tls/certs/ca-bundle.crt": bundle,
        "/etc/ssl/trust-source": trust_source,
    }
    for name, target in aliases.items():
        path = Path(name)
        if not _owned_link(path, "/etc/static" + name[4:]):
            return False
        if path.resolve(strict=True) != target:
            return False
    return True


def _retire_preview() -> None:
    """Resume interruption-safe cleanup while preserving unexpected paths."""
    unit = Path("/usr/local/lib/systemd/system/desktop-ca-preview.service")
    root = Path("/nix/var/nix/gcroots/desktop-trust-preview-20261021")
    try:
        package = root.readlink()
    except FileNotFoundError, OSError:
        return
    source = package / unit.name
    if (
        package.parent != Path("/nix/store")
        or not package.name.endswith("-desktop-trust-preview")
        or not _owned_link(root, str(package))
    ):
        return
    wanted = unit.parent / "sysinit.target.wants" / unit.name
    # Check every owned path before deleting any. Preserve unexpected content.
    # Retain the root last so interrupted removal can resume without the unit.
    if os.path.lexists(unit) and not _owned_link(unit, str(source)):
        return
    if os.path.lexists(wanted) and not _owned_link(wanted, str(unit)):
        return
    if os.path.lexists(wanted):
        wanted.unlink()
    if os.path.lexists(unit):
        unit.unlink()
    root.unlink()


def main() -> None:
    """Retire a known preview only after normal root PKI activation.

    Raises:
        PermissionError: The caller is not root.
        ValueError: Both configured trust paths were not supplied.

    """
    if os.geteuid() != 0:
        raise PermissionError
    if len(sys.argv) != ARGUMENT_COUNT:
        raise ValueError
    bundle, trust_source = (Path(value).resolve(strict=True) for value in sys.argv[1:])
    if _configured_trust(bundle, trust_source):
        _retire_preview()


if __name__ == "__main__":
    main()
