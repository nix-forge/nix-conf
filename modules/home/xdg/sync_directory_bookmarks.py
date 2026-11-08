"""Add configured directories to writable GTK bookmarks and KDE Places."""

import argparse
import fcntl
import json
import os
import tempfile
from pathlib import Path
from urllib.parse import unquote, urlsplit

from defusedxml import minidom


def identity(uri: str) -> str:
    """Compare local file URIs.

    Returns:
        A key independent of local escaping or trailing slashes.

    """
    parsed = urlsplit(uri)
    if parsed.scheme == "file" and parsed.netloc in {"", "localhost"}:
        return "file:" + os.path.normpath(unquote(parsed.path))
    return uri


def read_file(path: Path) -> bytes:
    """Read writable bookmark state.

    Returns:
        Original bytes, or empty bytes for an absent file.

    Raises:
        ValueError: The target is a foreign symlink.

    """
    if path.is_symlink():
        msg = f"{path} is a symlink; migrate it to a writable file before syncing"
        raise ValueError(msg)
    return path.read_bytes() if path.exists() else b""


def gtk_bookmarks(original: bytes, entries: list[dict[str, str]]) -> bytes:
    """Append missing GTK URIs.

    Returns:
        GTK bytes with original entries intact.

    """
    existing = {
        identity(line.split(" ", 1)[0])
        for line in original.decode("utf-8").splitlines()
        if line.strip()
    }
    additions = []
    for entry in entries:
        uri = Path(entry["path"]).as_uri()
        key = identity(uri)
        if key not in existing:
            additions.append(f"{uri} {entry['label']}\n")
            existing.add(key)
    if not additions:
        return original
    separator = b"\n" if original and not original.endswith(b"\n") else b""
    return original + separator + "".join(additions).encode("utf-8")


def kde_places(original: bytes, entries: list[dict[str, str]]) -> bytes:
    """Add local places while preserving KDE metadata.

    Returns:
        Original bytes if unchanged, or updated XML.

    Raises:
        ValueError: The document does not have an XBEL root.

    """
    # Retain namespace prefixes as well as metadata. KDE consumers can look
    # up bookmark:icon by its qualified name rather than namespace URI.
    document = minidom.parseString(original or b'<xbel version="1.0"/>')
    root = document.documentElement
    if root.tagName != "xbel":
        msg = "KDE Places must have an xbel root"
        raise ValueError(msg)
    existing = {
        identity(bookmark.getAttribute("href"))
        for bookmark in root.getElementsByTagName("bookmark")
    }
    changed = False
    for entry in entries:
        uri = Path(entry["path"]).as_uri()
        key = identity(uri)
        if key not in existing:
            bookmark = document.createElement("bookmark")
            bookmark.setAttribute("href", uri)
            title = document.createElement("title")
            title.appendChild(document.createTextNode(entry["label"]))
            bookmark.appendChild(title)
            root.appendChild(bookmark)
            existing.add(key)
            changed = True
    if not changed:
        return original
    return document.toxml(encoding="utf-8") + b"\n"


def atomic_write(path: Path, content: bytes) -> None:
    """Replace one bookmark file atomically, retaining its access permissions."""
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = path.stat().st_mode & 0o777 if path.exists() else 0o600
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            os.fchmod(stream.fileno(), mode)
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        Path(temporary).replace(path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def reconcile(
    home: Path,
    config_home: Path,
    data_home: Path,
    entries: list[dict[str, str]],
    *,
    dry_run: bool,
) -> None:
    """Validate every input before writing any bookmarks.

    Raises:
        ValueError: A path or label cannot be represented in bookmarks.

    """
    for entry in entries:
        if not Path(entry["path"]).is_absolute() or any(
            character in entry["label"] for character in "\r\n\0"
        ):
            msg = "Bookmark paths must be absolute and labels must be single lines"
            raise ValueError(msg)
    available = [entry for entry in entries if Path(entry["path"]).is_dir()]
    targets = [
        (config_home / "gtk-3.0/bookmarks", gtk_bookmarks),
        (data_home / "user-places.xbel", kde_places),
    ]
    # Preserve the legacy fallback before creating the modern GTK file.
    legacy = home / ".gtk-bookmarks"
    legacy_content = read_file(legacy)
    if legacy.exists():
        targets.append((legacy, gtk_bookmarks))
    updates = []
    for path, render in targets:
        original = read_file(path)
        seed = (
            legacy_content
            if path == config_home / "gtk-3.0/bookmarks" and not path.exists()
            else original
        )
        content = render(seed, available)
        if content != original:
            updates.append((path, content))
    if dry_run:
        return
    for path, content in updates:
        atomic_write(path, content)


def main() -> None:
    """Run activation reconciliation or a non-mutating preview."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--home", type=Path, default=Path.home())
    parser.add_argument("--config-home", required=True, type=Path)
    parser.add_argument("--data-home", required=True, type=Path)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    entries = json.loads(args.config.read_text(encoding="utf-8"))
    if args.dry_run:
        reconcile(args.home, args.config_home, args.data_home, entries, dry_run=True)
        return
    args.config_home.mkdir(parents=True, exist_ok=True)
    with (args.config_home / ".directory-bookmarks.lock").open(
        "a", encoding="utf-8"
    ) as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        reconcile(args.home, args.config_home, args.data_home, entries, dry_run=False)


if __name__ == "__main__":
    main()
