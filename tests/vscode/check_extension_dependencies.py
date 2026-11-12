"""Audit required extension dependencies in a built VS Code extension directory."""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import asdict, dataclass
from pathlib import Path


@dataclass(frozen=True)
class DependencyReport:
    """Describe the installed extension count and missing required companions."""

    extension_count: int
    missing: dict[str, list[str]]


def _invalid(path: Path, detail: str) -> ValueError:
    return ValueError(f"Invalid extension manifest {path}: {detail}")


def _scan(directory: Path) -> dict[str, tuple[str, ...]]:
    manifests: dict[str, tuple[str, ...]] = {}
    for child in sorted(directory.iterdir()):
        path = child / "package.json"
        if not child.is_dir() or not path.is_file():
            continue
        data = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            raise _invalid(path, "expected an object")
        publisher, name = data.get("publisher"), data.get("name")
        if not isinstance(publisher, str) or not publisher.strip():
            raise _invalid(path, "missing publisher")
        if not isinstance(name, str) or not name.strip():
            raise _invalid(path, "missing name")
        identifier = f"{publisher}.{name}".lower()
        if identifier in manifests:
            raise _invalid(path, f"duplicate identifier {identifier}")
        dependencies = data.get("extensionDependencies", [])
        if not isinstance(dependencies, list) or not all(
            isinstance(dependency, str) and dependency.strip()
            for dependency in dependencies
        ):
            raise _invalid(path, "extensionDependencies must be a list of identifiers")
        manifests[identifier] = tuple(dependency.lower() for dependency in dependencies)
    return manifests


def audit_extensions(
    directory: Path, builtin_directory: Path | None = None
) -> DependencyReport:
    """Find missing required companions, without expanding optional packs.

    Unreadable, malformed, and duplicate manifests propagate errors.

    Returns:
        Installed count and missing required companion identifiers.

    """
    installed = _scan(directory)
    available = set(installed)
    if builtin_directory is not None:
        available.update(_scan(builtin_directory))
    missing = {
        identifier: sorted(set(dependencies) - available)
        for identifier, dependencies in installed.items()
        if set(dependencies) - available
    }
    return DependencyReport(len(installed), missing)


def main() -> int:
    """Check a built extension tree and emit an inspectable JSON result.

    Returns:
        Zero when all required extensions are present, otherwise one.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("extensions", type=Path)
    parser.add_argument("--builtin-extensions", type=Path)
    args = parser.parse_args()
    try:
        result = audit_extensions(args.extensions, args.builtin_extensions)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    sys.stdout.write(json.dumps(asdict(result), sort_keys=True) + "\n")
    return int(bool(result.missing))


if __name__ == "__main__":
    sys.exit(main())
