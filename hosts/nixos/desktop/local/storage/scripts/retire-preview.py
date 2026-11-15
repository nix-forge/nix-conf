"""Retire only unchanged, recorded storage rollout overrides after OS adoption."""

import hashlib
import json
import sys
from pathlib import Path


def retire_entry(entry: dict[str, str]) -> bool:
    """Remove one unchanged override or recognize its exact declarative successor.

    Returns:
        Whether ownership has been safely reconciled.

    """
    path = Path(entry["path"])
    if not path.exists() and not path.is_symlink():
        return True
    if "symlink" in entry:
        if path.is_symlink() and str(path.readlink()) == entry["symlink"]:
            path.unlink()
            return True
        return path.is_symlink() and str(path.readlink()) == entry.get("adoptedLink")
    if path.is_symlink() and str(path.readlink()) == entry.get("restoreLink"):
        return True
    if (
        path.is_symlink()
        or not path.is_file()
        or hashlib.sha256(path.read_bytes()).hexdigest() != entry["sha256"]
    ):
        return False
    path.unlink()
    if "restoreLink" in entry:
        path.symlink_to(entry["restoreLink"])
    return True


def retire(manifest: Path) -> bool:
    """Remove owned overrides while preserving operator changes and their pin.

    Returns:
        Whether all recorded overrides were retired or superseded.

    """
    if not manifest.exists():
        return True
    record = json.loads(manifest.read_text(encoding="utf-8"))
    changed = [
        entry["path"] for entry in record["overrides"] if not retire_entry(entry)
    ]
    if changed:
        print(
            "Storage preview has operator changes; retaining its recovery pin and manifest",
            file=sys.stderr,
        )
        return False
    pin = Path(record["pin"])
    if pin.is_symlink() and str(pin.readlink()) == record["target"]:
        pin.unlink()
    elif pin.exists() or pin.is_symlink():
        print("Storage preview pin changed; preserving it", file=sys.stderr)
        return False
    manifest.rename(manifest.with_suffix(".retired.json"))
    return True


if __name__ == "__main__":
    retire(Path("/var/lib/desktop-storage/preview-manifest.json"))
