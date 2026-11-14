"""Inspect canonical macOS app identities and guide explicit capability tests."""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
import plistlib
import re
import subprocess  # ruff: ignore[suspicious-subprocess-import]
import sys
import tempfile
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import TYPE_CHECKING, NoReturn, TypedDict

if TYPE_CHECKING:
    from collections.abc import Sequence

SERVICES = frozenset({
    "accessibility",
    "local-network",
    "camera",
    "microphone",
    "screen-recording",
    "input-monitoring",
    "full-disk-access",
    "apple-events",
    "notifications",
    "browser-integration",
    "protected-files",
    "background-items",
})
MINIMUM_OS = 13
MAXIMUM_ERROR = 1000
KEY = re.compile(r"[a-zA-Z0-9][a-zA-Z0-9_.-]*\Z")


class ReadinessError(Exception):
    """A manifest, native inspection, or evidence operation failed safely."""


def fail(message: str) -> NoReturn:
    """Reject an invalid operation.

    Raises:
        ReadinessError: With the actionable rejection reason.

    """
    raise ReadinessError(message)


def mapping(value: object) -> dict[str, object]:
    """Validate a JSON object without trusting nested values.

    Returns:
        Validated string-keyed members.

    """
    if not isinstance(value, dict) or not all(isinstance(key, str) for key in value):
        fail("Expected an object")
    return dict(value)


def text(value: object) -> str:
    """Require nonempty text from an external document.

    Returns:
        The original nonempty string.

    """
    if not isinstance(value, str) or not value.strip():
        fail("Expected nonempty text")
    return value


def key(value: str) -> str:
    """Reject identifiers that could escape private evidence paths.

    Returns:
        The validated identifier.

    """
    if not KEY.fullmatch(value):
        fail("Invalid application or feature key")
    return value


@dataclass(frozen=True)
class Feature:
    """One explicitly selected feature, independent of privacy state."""

    name: str
    service: str
    reason: str
    source: str
    instruction: str
    minimum_os: int


@dataclass(frozen=True)
class App:
    """Expected identity at one canonical copied bundle path."""

    name: str
    bundle: str
    bundle_id: str
    team_id: str | None
    features: tuple[Feature, ...]


@dataclass(frozen=True)
class Manifest:
    """The versioned Nix-generated input to the readiness command."""

    apps_directory: Path
    state_directory: Path
    apps: tuple[App, ...]


def load_manifest(path: Path) -> Manifest:
    """Validate the entire manifest before native commands or writes.

    Returns:
        The complete validated manifest.

    """
    data = mapping(json.loads(path.read_text(encoding="utf-8")))
    if type(data.get("schemaVersion")) is not int or data.get("schemaVersion") != 1:
        fail("Unsupported manifest version")
    apps = []
    bundles: set[str] = set()
    identifiers: set[str] = set()
    for name, raw in sorted(mapping(data.get("apps")).items()):
        item = mapping(raw)
        bundle = text(item.get("bundle"))
        identifier = text(item.get("bundleId"))
        if Path(bundle).name != bundle or not bundle.endswith(".app"):
            fail("Expected a top-level .app bundle")
        if bundle.casefold() in bundles or identifier in identifiers:
            fail("Duplicate bundle path or identifier")
        bundles.add(bundle.casefold())
        identifiers.add(identifier)
        team = item.get("teamId")
        if team is not None:
            team = text(team)
        features = []
        for feature_name, raw_feature in sorted(mapping(item.get("features")).items()):
            feature = mapping(raw_feature)
            service = text(feature.get("service"))
            minimum = feature.get("minimumOS")
            source = text(feature.get("source"))
            if service not in SERVICES or not source.startswith("https://"):
                fail("Unsupported service or evidence source")
            if type(minimum) is not int or minimum < MINIMUM_OS:
                fail("Expected a supported macOS major version")
            features.append(
                Feature(
                    key(feature_name),
                    service,
                    text(feature.get("reason")),
                    source,
                    text(feature.get("instruction")),
                    max(15, minimum) if service == "local-network" else minimum,
                )
            )
        apps.append(App(key(name), bundle, identifier, team, tuple(features)))
    apps_directory = Path(text(data.get("appsDirectory")))
    state_directory = Path(text(data.get("stateDirectory")))
    if not apps_directory.is_absolute() or not state_directory.is_absolute():
        fail("Manifest directories must be absolute")
    return Manifest(apps_directory, state_directory, tuple(apps))


@dataclass(frozen=True)
class Identity:
    """Verified installed identity; never a permission grant."""

    bundle_id: str
    version: str
    team_id: str | None
    requirement: str
    cdhash: str
    signing_kind: str
    fingerprint: str


def digest(value: object) -> str:
    """Hash a deterministic observation without persisting private input.

    Returns:
        A stable hexadecimal SHA-256 digest.

    """
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


class NativeInspector:
    """Read only metadata and Apple's own signature verifier."""

    @staticmethod
    def run(arguments: list[str]) -> str:
        """Run a fixed native command with bounded runtime and output capture.

        Returns:
            Combined output from the successful native command.

        """
        result = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Fixed native commands, no shell.
            arguments, capture_output=True, text=True, timeout=30, check=False
        )
        if result.returncode:
            fail((result.stderr.strip() or "Native inspection failed")[:MAXIMUM_ERROR])
        return result.stdout + result.stderr

    def system(self) -> tuple[str, str]:
        """Return OS version/build without prompting or starting an application.

        Returns:
            The product version and build version.

        """
        if sys.platform != "darwin":
            fail("Native readiness inspection requires macOS")
        return (
            self.run(["/usr/bin/sw_vers", "-productVersion"]).strip(),
            self.run(["/usr/bin/sw_vers", "-buildVersion"]).strip(),
        )

    def inspect(self, path: Path) -> Identity:
        """Verify all bundle architectures before accepting installed metadata.

        Returns:
            Verified bundle identity and its fingerprint.

        """
        if path.is_symlink() or not path.is_dir():
            fail("Canonical app must be an existing copied directory")
        with (path / "Contents/Info.plist").open("rb") as handle:
            metadata = mapping(plistlib.load(handle))
        identifier = text(metadata.get("CFBundleIdentifier"))
        version = text(
            metadata.get("CFBundleShortVersionString")
            or metadata.get("CFBundleVersion")
        )
        self.run([
            "/usr/bin/codesign",
            "--verify",
            "--deep",
            "--strict",
            "--all-architectures",
            str(path),
        ])
        details = self.run([
            "/usr/bin/codesign",
            "--display",
            "--verbose=4",
            "-r-",
            str(path),
        ])
        fields = dict(
            line.split("=", 1) for line in details.splitlines() if "=" in line
        )
        if fields.get("Identifier") != identifier:
            fail("Signed executable identifier does not match Info.plist")
        requirement = text(
            (fields.get("designated ") or fields.get("# designated ") or "")
            .removeprefix("> ")
            .strip()
        )
        cdhash = text(fields.get("CDHash"))
        team = fields.get("TeamIdentifier")
        if team == "not set":
            team = None
        kind = "ad-hoc" if fields.get("Signature") == "adhoc" else "certificate"
        fingerprint = digest([
            str(path.resolve()),
            identifier,
            version,
            team,
            requirement,
            cdhash,
        ])
        return Identity(
            identifier, version, team, requirement, cdhash, kind, fingerprint
        )

    def open(self, path: Path, *, settings: bool) -> None:
        """Open only the explicitly requested verified app or System Settings."""
        self.run(
            ["/usr/bin/open", "-a", "System Settings"]
            if settings
            else ["/usr/bin/open", str(path)]
        )


def observation_key(
    app: App, feature: Feature, identity: Identity, system: tuple[str, str]
) -> str:
    """Invalidate evidence on feature, identity, OS version or build changes.

    Returns:
        A key bound to the tested feature, bundle and OS.

    """
    return digest([
        app.name,
        feature.name,
        feature.service,
        feature.reason,
        feature.instruction,
        identity.fingerprint,
        system,
    ])


def receipt_path(manifest: Manifest, app: App, feature: Feature) -> Path:
    """Keep each receipt at a stable, validated, non-user-selectable filename.

    Returns:
        The selected feature receipt path.

    """
    return manifest.state_directory / (digest([app.name, feature.name]) + ".json")


def read_receipt(path: Path, expected: str) -> dict[str, object] | None:
    """Read historical evidence without treating it as current authorization.

    Returns:
        Historical evidence, stale evidence metadata, or None.

    """
    if not path.exists():
        return None
    if path.is_symlink() or path.parent.is_symlink():
        return {"stale": True, "error": "Evidence symlink rejected"}
    try:
        data = mapping(json.loads(path.read_text(encoding="utf-8")))
        valid = (
            type(data.get("schemaVersion")) is int
            and data.get("schemaVersion") == 1
            and isinstance(data.get("result"), str)
            and data.get("result") in {"passed", "failed"}
            and data.get("origin") == "gui-app"
            and data.get("provenance") == "operator-reported-feature-test"
            and isinstance(data.get("evidence"), str)
            and isinstance(data.get("verifiedAt"), str)
            and isinstance(data.get("appVersion"), str)
            and isinstance(data.get("identityFingerprint"), str)
            and isinstance(data.get("osBuild"), str)
        )
        if not valid:
            fail("Malformed receipt")
    except OSError, ValueError, ReadinessError:
        return {"stale": True, "error": "Unreadable or malformed historical evidence"}
    return {**data, "stale": data.get("observationKey") != expected}


def write_receipt(path: Path, receipt: dict[str, object]) -> None:
    """Serialize explicit verification writes and atomically replace a receipt."""
    directory = path.parent
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    if directory.is_symlink() or directory.stat().st_uid != os.getuid():
        fail("Evidence directory must be owned by the current user and not a symlink")
    if directory.stat().st_mode & 0o077:
        fail("Evidence directory must be private (mode 0700)")
    lock_fd = os.open(
        directory / ".lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600
    )
    temporary: Path | None = None
    try:
        with os.fdopen(lock_fd, "w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            with tempfile.NamedTemporaryFile(
                mode="w",
                encoding="utf-8",
                dir=directory,
                prefix=".receipt-",
                delete=False,
            ) as handle:
                temporary = Path(handle.name)
                json.dump(receipt, handle, sort_keys=True)
                handle.write("\n")
                handle.flush()
                os.fsync(handle.fileno())
            temporary.replace(path)
            temporary = None
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def inspect_apps(
    manifest: Manifest, inspector: NativeInspector
) -> tuple[dict[str, Identity], dict[str, str]]:
    """Reject invalid signatures, mismatched identities and duplicate observed IDs.

    Returns:
        Accepted identities and actionable failures by application key.

    """
    identities: dict[str, Identity] = {}
    errors: dict[str, str] = {}
    observed: dict[str, str] = {}
    for app in manifest.apps:
        path = manifest.apps_directory / app.bundle
        try:
            identity = inspector.inspect(path)
        except (
            OSError,
            ValueError,
            ReadinessError,
            subprocess.TimeoutExpired,
        ) as error:
            errors[app.name] = str(error)
            continue
        if identity.bundle_id in observed:
            errors[observed[identity.bundle_id]] = (
                "Duplicate observed bundle identifier"
            )
            errors[app.name] = "Duplicate observed bundle identifier"
        observed[identity.bundle_id] = app.name
        if identity.bundle_id != app.bundle_id or (
            app.team_id is not None and identity.team_id != app.team_id
        ):
            errors[app.name] = (
                "Installed bundle or vendor team does not match the manifest"
            )
        identities[app.name] = identity
    return identities, errors


class FeatureReport(TypedDict):
    """One capability status with historical evidence clearly separated."""

    key: str
    service: str
    status: str
    observed: str
    reason: str
    nextAction: str
    source: str
    lastVerification: dict[str, object] | None


class AppReport(TypedDict):
    """An identity result and its selected capabilities."""

    key: str
    bundle: str
    identityStatus: str
    error: str | None
    bundleId: str | None
    version: str | None
    signingKind: str | None
    features: list[FeatureReport]


class Snapshot(TypedDict):
    """Versioned report emitted in both human and JSON views."""

    schemaVersion: int
    osVersion: str
    osBuild: str
    apps: list[AppReport]


def report(manifest: Manifest, inspector: NativeInspector) -> Snapshot:
    """Produce a read-only readiness snapshot; historical receipts cannot grant access.

    Returns:
        A snapshot separating identity from capability authorization.

    """
    system = inspector.system()
    major = int(system[0].split(".")[0])
    identities, errors = inspect_apps(manifest, inspector)
    apps: list[AppReport] = []
    for app in manifest.apps:
        identity = identities.get(app.name)
        features: list[FeatureReport] = []
        for feature in app.features:
            status = "unknown"
            if app.name in errors:
                status = "blocked-identity"
            elif major < feature.minimum_os:
                status = "unsupported"
            historical = (
                None
                if identity is None
                else read_receipt(
                    receipt_path(manifest, app, feature),
                    observation_key(app, feature, identity, system),
                )
            )
            features.append({
                "key": feature.name,
                "service": feature.service,
                "status": status,
                "observed": "unknown",
                "reason": feature.reason,
                "nextAction": feature.instruction,
                "source": feature.source,
                "lastVerification": historical,
            })
        apps.append({
            "key": app.name,
            "bundle": app.bundle,
            "identityStatus": "blocked-identity" if app.name in errors else "ready",
            "error": errors.get(app.name),
            "bundleId": identity.bundle_id if identity else None,
            "version": identity.version if identity else None,
            "signingKind": identity.signing_kind if identity else None,
            "features": features,
        })
    return {
        "schemaVersion": 1,
        "osVersion": system[0],
        "osBuild": system[1],
        "apps": apps,
    }


def selection(manifest: Manifest, names: Sequence[str]) -> tuple[App, Feature]:
    """Resolve only configured applications and enabled feature names.

    Returns:
        The selected application and enabled feature.

    """
    for app in manifest.apps:
        if app.name == names[0]:
            for feature in app.features:
                if feature.name == names[1]:
                    return app, feature
    fail("Application/feature is not selected in the manifest")


def main(
    arguments: Sequence[str] | None = None, *, inspector: NativeInspector | None = None
) -> int:
    """Run read-only checks, explicit UI guidance, or record a real GUI feature test.

    Returns:
        Zero for successful explicit operations, one for errors, two for unknown capabilities.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument(
        "--check",
        action="store_true",
        help="read metadata and historical evidence only",
    )
    modes.add_argument("--guide", nargs=2, metavar=("APP", "FEATURE"))
    modes.add_argument(
        "--verify",
        nargs=2,
        metavar=("APP", "FEATURE"),
        help="record an explicitly performed feature test, never just a consent toggle",
    )
    parser.add_argument("--json", action="store_true")
    parser.add_argument(
        "--open", choices=["app", "settings"], help="explicitly open UI during --guide"
    )
    parser.add_argument("--result", choices=["passed", "failed"])
    parser.add_argument("--origin", choices=["gui-app"])
    parser.add_argument(
        "--evidence",
        help="describe the actual GUI feature tested; keep private data out",
    )
    args = parser.parse_args(arguments)
    try:
        return execute(args, inspector or NativeInspector())
    except (OSError, ValueError, ReadinessError, subprocess.TimeoutExpired) as error:
        sys.stderr.write(f"hm-macos-readiness: {error}\n")
        return 1


def execute(args: argparse.Namespace, native: NativeInspector) -> int:
    """Dispatch validated command modes.

    Returns:
        The public command exit status.

    """
    if args.open and not args.guide:
        fail("--open requires --guide")
    if (args.result or args.origin or args.evidence) and not args.verify:
        fail("Evidence arguments require --verify")
    manifest = load_manifest(args.manifest)
    if args.guide or args.verify:
        return guide_or_verify(args, native, manifest)
    snapshot = report(manifest, native)
    if args.json:
        sys.stdout.write(json.dumps(snapshot, sort_keys=True) + "\n")
    else:
        for app in snapshot["apps"]:
            sys.stdout.write(
                f"{app['key']}: identity {app['identityStatus']}"
                + (f" ({app['error']})" if app["error"] else "")
                + "\n"
            )
            for feature in app["features"]:
                sys.stdout.write(
                    f"  {feature['key']}: {feature['status']} — {feature['nextAction']}\n"
                )
    apps = snapshot["apps"]
    if any(app["identityStatus"] == "blocked-identity" for app in apps):
        return 1
    return 2 if any(app["features"] for app in apps) else 0


def guide_or_verify(
    args: argparse.Namespace, native: NativeInspector, manifest: Manifest
) -> int:
    """Guide one capability or record an operator-reported GUI feature test.

    Returns:
        Zero after successful guidance or evidence recording.

    """
    app, feature = selection(manifest, args.guide or args.verify)
    system = native.system()
    identities, errors = inspect_apps(manifest, native)
    if app.name in errors:
        fail(errors[app.name])
    if int(system[0].split(".")[0]) < feature.minimum_os:
        fail("Capability unsupported on this OS")
    if args.guide:
        if args.open:
            native.open(
                manifest.apps_directory / app.bundle, settings=args.open == "settings"
            )
        output: object = {
            "app": app.name,
            "feature": feature.name,
            "instruction": feature.instruction,
            "source": feature.source,
        }
    else:
        if (
            not args.result
            or args.origin != "gui-app"
            or not args.evidence
            or not args.evidence.strip()
        ):
            fail(
                "--verify requires --result, --origin gui-app and --evidence describing a performed feature test"
            )
        receipt: dict[str, object] = {
            "schemaVersion": 1,
            "result": args.result,
            "origin": args.origin,
            "evidence": args.evidence,
            "verifiedAt": datetime.now(UTC).isoformat(),
            "observationKey": observation_key(
                app, feature, identities[app.name], system
            ),
            "provenance": "operator-reported-feature-test",
            "app": app.name,
            "feature": feature.name,
            "service": feature.service,
            "bundleId": identities[app.name].bundle_id,
            "appVersion": identities[app.name].version,
            "identityFingerprint": identities[app.name].fingerprint,
            "osVersion": system[0],
            "osBuild": system[1],
        }
        write_receipt(receipt_path(manifest, app, feature), receipt)
        output = {"recorded": True, "currentAuthorization": "unknown", **receipt}
    sys.stdout.write(
        (
            json.dumps(output, sort_keys=True)
            if args.json
            else json.dumps(output, indent=2)
        )
        + "\n"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
