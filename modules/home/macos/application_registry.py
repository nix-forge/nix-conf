"""Reconcile copied macOS apps without resetting unrelated registrations."""

from __future__ import annotations

import argparse
import fcntl
import json
import logging
import plistlib
import re
import subprocess  # ruff: ignore[suspicious-subprocess-import]
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING, Literal, Protocol, override

if TYPE_CHECKING:
    from collections.abc import Sequence

LSREGISTER = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
STORE_APP = re.compile(r"/nix/store/[^/]+/Applications/[^/]+\.app")
LOGGER = logging.getLogger(__name__)


@dataclass(frozen=True)
class Application:
    """A canonical copied application with a verified bundle identity."""

    path: Path
    identifier: str


class Registry(Protocol):
    """The native registration boundary, replaced by fixtures in behavior tests."""

    def paths(self, identifiers: Sequence[str]) -> dict[str, list[str]]:
        """Return application URLs for each bundle identifier."""
        ...

    def register(self, path: Path) -> None:
        """Register the canonical bundle."""
        ...

    def unregister(self, path: Path) -> None:
        """Unregister an obsolete store bundle."""
        ...


class NativeRegistry(Registry):
    """Use AppKit for inventory and Launch Services for scoped mutations."""

    def __init__(self, query_script: Path) -> None:
        """Retain the packaged native query source."""
        self.query_script = query_script

    @override
    def paths(self, identifiers: Sequence[str]) -> dict[str, list[str]]:
        """Read matching URLs.

        Returns:
            Available application paths by bundle identifier.

        Raises:
            ValueError: The native output is malformed.

        """
        completed = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Fixed native executable and argument array.
            [
                "/usr/bin/osascript",
                "-l",
                "JavaScript",
                str(self.query_script),
                *identifiers,
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        data = json.loads(completed.stdout)
        dump = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Read-only native registry dump.
            [LSREGISTER, "-dump"], check=True, capture_output=True, text=True
        )
        disabled = disabled_registrations(dump.stdout)
        result = {}
        for identifier in identifiers:
            paths = data[identifier]["available"]
            if not isinstance(paths, list) or not all(
                isinstance(p, str) for p in paths
            ):
                msg = "Invalid application URL inventory"
                raise ValueError(msg)
            # AppKit can retain unregistered URLs as launch-disabled tombstones.
            # They cannot launch and must not make later activations fail.
            result[identifier] = [
                p for p in paths if p not in disabled and Path(p).exists()
            ]
        return result

    @override
    def register(self, path: Path) -> None:
        """Refresh only the specified app, without recursively registering helpers."""
        subprocess.run([LSREGISTER, "-f", str(path)], check=True)  # ruff: ignore[subprocess-without-shell-equals-true] - Fixed native executable.

    @override
    def unregister(self, path: Path) -> None:
        """Retire only the specified obsolete registration."""
        subprocess.run([LSREGISTER, "-u", str(path)], check=True)  # ruff: ignore[subprocess-without-shell-equals-true] - Fixed native executable.


def disabled_registrations(dump: str) -> set[str]:
    """Identify explicitly disabled store/recovery records, retaining unknown formats.

    Returns:
        Exact store/recovery app paths marked launch-disabled in the native dump.

    """
    result = set()
    for block in re.split(r"(?m)^-{20,}\s*$", dump):
        path = re.search(r"(?m)^path:\s+(.+?)\s+\(0x[0-9a-fA-F]+\)\s*$", block)
        flags = re.search(r"(?m)^bundle flags:\s+(.+)$", block)
        if not path or not flags or "launch-disabled" not in flags[1].split():
            continue
        bundle = Path(path[1])
        recovery = (
            bundle.name.endswith(".app")
            and bundle.parent.name.startswith(".hm-app-update-")
            and bundle.parent.name.endswith(".noindex")
        )
        if STORE_APP.fullmatch(path[1]) or recovery:
            result.add(path[1])
    return result


def bundle_identifier(path: Path) -> str:
    """Read identity from the actual bundle, including binary Info plists.

    Returns:
        The declared bundle identifier.

    Raises:
        ValueError: The bundle does not declare a usable identifier.

    """
    with (path / "Contents/Info.plist").open("rb") as stream:
        identifier = plistlib.load(stream).get("CFBundleIdentifier")
    if not isinstance(identifier, str) or not identifier:
        msg = f"Application has no bundle identifier: {path}"
        raise ValueError(msg)
    return identifier


def applications(directory: Path) -> list[Application]:
    """Validate the copied inventory before changing registrations.

    Returns:
        Canonical bundles with distinct identifiers.

    Raises:
        ValueError: The inventory contains links, non-bundles, or duplicate IDs.

    """
    if directory.is_symlink() or not directory.is_dir():
        msg = f"Expected a real copied application directory: {directory}"
        raise ValueError(msg)
    result = []
    identifiers = set()
    for path in sorted(directory.glob("*.app")):
        if path.is_symlink() or not path.is_dir():
            msg = f"Expected a copied application bundle: {path}"
            raise ValueError(msg)
        identifier = bundle_identifier(path)
        if identifier in identifiers:
            msg = f"Multiple copied bundles share an identifier: {identifier}"
            raise ValueError(msg)
        identifiers.add(identifier)
        result.append(Application(path, identifier))
    return result


def legacy_links(apps: Sequence[Application], directory: Path) -> list[Path]:
    """Select old store links with matching names and bundle identities.

    Returns:
        Only confirmed superseded symlinks, never manual app directories.

    """
    links = []
    for app in apps:
        candidate = directory / app.path.name
        if candidate == app.path or not candidate.is_symlink():
            continue
        target = candidate.resolve()
        if (
            STORE_APP.fullmatch(str(target))
            and target.is_dir()
            and bundle_identifier(target) == app.identifier
        ):
            links.append(candidate)
    return links


def archive_links(links: Sequence[Path], state_dir: Path) -> None:
    """Journal symlinks before moving them into private recovery storage.

    Raises:
        ValueError: A link changed during migration.

    """
    if not links:
        return
    backup = Path(tempfile.mkdtemp(prefix="migration-", dir=state_dir))
    for index, link in enumerate(links):
        target = str(link.readlink())
        saved = backup / f"{index}-{link.name}"
        journal = backup / f"{index}.json"
        journal.write_text(
            json.dumps({"original": str(link), "target": target, "saved": str(saved)})
            + "\n"
        )
        if str(link.readlink()) != target:
            msg = f"Legacy application link changed during migration: {link}"
            raise ValueError(msg)
        link.rename(saved)
        LOGGER.info("Archived obsolete application link: %s -> %s", link, saved)


def update_registrations(
    apps: Sequence[Application],
    before: dict[str, list[str]],
    registry: Registry,
    *,
    dry_run: bool,
) -> None:
    """Retire store candidates and refresh canonical bundles, or preview the plan."""
    for app in apps:
        for path in before[app.identifier]:
            if STORE_APP.fullmatch(path):
                if dry_run:
                    LOGGER.info("Would unregister: %s", path)
                else:
                    registry.unregister(Path(path))
        if dry_run:
            LOGGER.info("Would register: %s", app.path)
        else:
            registry.register(app.path)


def verify(apps: Sequence[Application], registry: Registry) -> None:
    """Require canonical copies and no competing store registrations.

    Raises:
        ValueError: Native registration did not converge.

    """
    after = registry.paths([app.identifier for app in apps])
    for app in apps:
        paths = after[app.identifier]
        if str(app.path) not in paths or any(STORE_APP.fullmatch(p) for p in paths):
            msg = (
                f"Application registration did not converge: {app.identifier}: {paths}"
            )
            raise ValueError(msg)
    LOGGER.info("Verified %s canonical application registrations", len(apps))


def reconcile(
    apps_dir: Path,
    legacy_dir: Path,
    state_dir: Path,
    registry: Registry,
    *,
    mode: Literal["repair", "dry-run", "check"] = "repair",
) -> None:
    """Make copied apps canonical while preserving unrelated apps and store files.

    Raises:
        ValueError: Check mode finds an obsolete legacy symlink.

    """
    apps = applications(apps_dir)
    identifiers = [app.identifier for app in apps]
    before = registry.paths(identifiers)
    links = legacy_links(apps, legacy_dir)
    if mode != "check":
        if mode != "dry-run":
            archive_links(links, state_dir)
        else:
            for link in links:
                LOGGER.info("Would archive obsolete link: %s", link)
        update_registrations(apps, before, registry, dry_run=mode == "dry-run")
    if mode == "dry-run":
        return
    verify(apps, registry)
    if mode == "check" and links:
        msg = "Obsolete application symlinks remain"
        raise ValueError(msg)


def execute(args: argparse.Namespace) -> None:
    """Run previews read-only and serialize mutating activations."""
    registry = NativeRegistry(args.query_script)
    if args.dry_run or args.check:
        reconcile(
            args.apps_dir,
            args.legacy_dir,
            args.state_dir,
            registry,
            mode="dry-run" if args.dry_run else "check",
        )
    else:
        args.state_dir.mkdir(parents=True, mode=0o700, exist_ok=True)
        with (args.state_dir / "activation.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            reconcile(args.apps_dir, args.legacy_dir, args.state_dir, registry)


def main() -> None:
    """Serialize activation repairs and expose read-only checks and previews."""
    parser = argparse.ArgumentParser(description=__doc__)
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser.add_argument("--apps-dir", type=Path)
    parser.add_argument("--legacy-dir", type=Path)
    parser.add_argument("--state-dir", type=Path)
    parser.add_argument("--query-script", required=True, type=Path)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--dry-run", action="store_true")
    modes.add_argument("--check", action="store_true")
    modes.add_argument("--registered-paths", nargs="+")
    args = parser.parse_args()
    if not args.registered_paths and not all((
        args.apps_dir,
        args.legacy_dir,
        args.state_dir,
    )):
        parser.error(
            "--apps-dir, --legacy-dir and --state-dir are required for reconciliation"
        )
    try:
        if args.registered_paths:
            sys.stdout.write(
                json.dumps(
                    NativeRegistry(args.query_script).paths(args.registered_paths)
                )
                + "\n"
            )
        else:
            execute(args)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Application registration failed: {error}\n")


if __name__ == "__main__":
    main()
