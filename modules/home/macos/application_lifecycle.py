"""Protect signed application copies and reconcile their live executable identity.

No operation grants privacy permission. Run acceptance probes inside the actual
GUI app; a healthy SSH or launchd probe cannot establish its Local Network grant.
"""

from __future__ import annotations

import argparse
import ctypes
import fcntl
import json
import os
import plistlib
import pwd
import re
import shutil
import stat
import subprocess  # ruff: ignore[suspicious-subprocess-import]
import sys
import tempfile
import uuid
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Generator
from contextlib import contextmanager, nullcontext, suppress
from dataclasses import dataclass
from pathlib import Path
from typing import NoReturn

PROCESS_IDENTITY_SIZE = 56
CDHASH_SIZE = 20
ROOT_STATE = Path("/var/run/macos-application-registry")

LSREGISTER = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"


class LifecycleError(Exception):
    """The requested operation cannot safely proceed."""


def command(*args: str) -> str:
    """Run a bounded native command, preserving actionable failures.

    Returns:
        The validated operation result.

    """
    # Signing services can stall transiently (including on wake) even for a
    # metadata query. Keep their deadline distinct from ordinary native calls.
    timeout = 120 if args[0] == "/usr/bin/codesign" else 30
    # This child performs multiple independently bounded signature inspections.
    # Killing its launcher at the per-command deadline abandons a valid check.
    if args[:2] == ("/bin/launchctl", "asuser") and args[-2:] == ("--mode", "check"):
        timeout = 900
    result = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Native executables with explicit argv.
        args, capture_output=True, text=True, timeout=timeout, check=False
    )
    if result.returncode:
        fail(f"{args[0]}: {result.stderr.strip()[:1000]}")
    return result.stdout + result.stderr


def fail(message: str) -> NoReturn:
    """Reject an unsafe operation.

    Raises:
        LifecycleError: With an actionable reason.

    """
    raise LifecycleError(message)


class ProcessIdentity(ctypes.Structure):
    """Apple proc_uniqidentifierinfo; fail closed if this capability changes."""

    _fields_ = [
        ("uuid", ctypes.c_ubyte * 16),
        ("uniqueid", ctypes.c_uint64),
        ("parent_uniqueid", ctypes.c_uint64),
        ("idversion", ctypes.c_int32),
        ("original_parent_idversion", ctypes.c_int32),
        ("reserved2", ctypes.c_uint64),
        ("reserved3", ctypes.c_uint64),
    ]


def process_identity(pid: int) -> tuple[str, int, int, str]:
    """Read the loaded image, rather than reopening its executable pathname.

    Returns:
        The validated operation result.

    """
    library = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
    query = getattr(library, "proc_pidinfo", None)
    if query is None:
        fail("Native loaded identity API is unavailable")
    query.argtypes = [
        ctypes.c_int,
        ctypes.c_int,
        ctypes.c_uint64,
        ctypes.c_void_p,
        ctypes.c_int,
    ]
    query.restype = ctypes.c_int
    info = ProcessIdentity()
    size = ctypes.sizeof(info)
    if (
        size != PROCESS_IDENTITY_SIZE
        or query(pid, 17, 0, ctypes.byref(info), size) != size
    ):
        fail(
            f"Cannot establish loaded identity for PID {pid}; retry after a normal Quit/reopen"
        )
    kernel = ctypes.CDLL("/usr/lib/libSystem.B.dylib", use_errno=True)
    csops = getattr(kernel, "csops", None)
    if csops is None:
        fail("Native live signing API is unavailable")
    csops.argtypes = [ctypes.c_int, ctypes.c_uint, ctypes.c_void_p, ctypes.c_size_t]
    csops.restype = ctypes.c_int
    digest = (ctypes.c_ubyte * CDHASH_SIZE)()
    if csops(pid, 5, digest, CDHASH_SIZE) != 0 or not any(digest):
        fail(f"Cannot establish live signing hash for PID {pid}")
    return (
        str(uuid.UUID(bytes=bytes(info.uuid))).upper(),
        info.uniqueid,
        info.idversion,
        bytes(digest).hex(),
    )


class Native:
    """Small native boundary shared by preflight, copy, and health checks."""

    def __init__(
        self, query_script: str, rsync: str, registry_helper: str = ""
    ) -> None:
        """Retain explicit native tool paths."""
        self.query_script = query_script
        self.rsync = rsync
        self.registry_helper = registry_helper

    @staticmethod
    def inspect(path: Path, app: dict) -> dict:
        """Require the expected vendor and intact code in every architecture.

        Returns:
            The validated operation result.

        """
        with (path / "Contents/Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
        if info.get("CFBundleIdentifier") != app["bundleId"]:
            fail(f"Unexpected bundle identifier: {path}")
        executable = info.get("CFBundleExecutable", "")
        if not executable or Path(executable).name != executable:
            fail(f"Invalid executable name: {path}")
        command(
            "/usr/bin/codesign",
            "--verify",
            "--deep",
            "--strict",
            "--all-architectures",
            str(path),
        )
        image = path / "Contents/MacOS" / executable
        # Enumerate slices so a Rosetta process is checked against its own
        # architecture's verified code, rather than the machine's default slice.
        slices = re.findall(
            r"UUID: ([A-Fa-f0-9-]+) \(([^)]+)\)",
            command("/usr/bin/dwarfdump", "--uuid", str(image)),
        )
        if not slices:
            fail(f"No Mach-O UUID: {image}")
        hashes = []
        for _, architecture in slices:
            signature = command(
                "/usr/bin/codesign",
                "-d",
                "--verbose=4",
                "--arch",
                architecture,
                str(path),
            )
            fields = dict(
                re.findall(r"(?m)^(Identifier|TeamIdentifier|CDHash)=(.+)$", signature)
            )
            digest = fields.get("CDHash", "").lower()
            if (
                fields.get("Identifier") != app["bundleId"]
                or fields.get("TeamIdentifier") != app["teamId"]
                or not re.fullmatch(r"[0-9a-f]{40}", digest)
            ):
                fail(f"Unexpected signing identity: {path} ({architecture})")
            hashes.append(digest)
        return {
            "cdhashes": hashes,
            "build": str(info.get("CFBundleVersion", "")),
            "uuids": [value.upper() for value, _ in slices],
        }

    def running(self, app: dict) -> list[dict]:
        """Return the workspace application snapshot.

        Returns:
            The validated operation result.

        """
        data = json.loads(
            command(
                "/usr/bin/osascript",
                "-l",
                "JavaScript",
                self.query_script,
                app["bundleId"],
            )
        )
        running = data[app["bundleId"]]["running"]
        if not isinstance(running, list):
            fail("Invalid native running application inventory")
        return running

    @staticmethod
    def process(pid: int) -> tuple[str, int, int, str]:
        """Read a PID identity with exec/reuse protection at the caller.

        Returns:
            The validated operation result.

        """
        return process_identity(pid)

    def copy(self, source: Path, destination: Path) -> None:
        """Match HM's signature-safe copy flags, without touching a live bundle."""
        destination.mkdir()
        command(
            self.rsync,
            "--recursive",
            "--checksum",
            "--perms",
            "--links",
            "--copy-unsafe-links",
            "--specials",
            "--chmod=+w",
            str(source) + "/",
            str(destination) + "/",
        )

    @staticmethod
    def move(source: Path, destination: Path) -> None:
        """Atomically rename a whole bundle without replacing another path."""
        libc = ctypes.CDLL("/usr/lib/libSystem.B.dylib", use_errno=True)
        rename = libc.renameatx_np
        rename.argtypes = [
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_uint,
        ]
        rename.restype = ctypes.c_int
        if rename(-2, os.fsencode(source), -2, os.fsencode(destination), 4) != 0:
            fail(f"Exclusive app rename failed (errno {ctypes.get_errno()})")
        for parent in {source.parent, destination.parent}:
            descriptor = os.open(parent, os.O_RDONLY)
            try:
                os.fsync(descriptor)
            finally:
                os.close(descriptor)

    @staticmethod
    def swap(staged: Path, installed: Path) -> None:
        """Atomically exchange directories; keep the complete old app as backup."""
        if not installed.exists():
            Native.move(staged, installed)
            return
        libc = ctypes.CDLL("/usr/lib/libSystem.B.dylib", use_errno=True)
        swap = libc.renameatx_np
        swap.argtypes = [
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_uint,
        ]
        swap.restype = ctypes.c_int
        if swap(-2, os.fsencode(staged), -2, os.fsencode(installed), 2) != 0:
            fail(
                f"Atomic app exchange failed (errno {ctypes.get_errno()}); original retained"
            )

    @staticmethod
    def register(path: Path) -> None:
        """Refresh metadata only in the current logged-in user's registry."""
        command(LSREGISTER, "-f", str(path))

    def unregister(self, path: Path, app: dict) -> None:
        """Retire an eligible URL; an absent/disabled backup needs no mutation."""
        unregister_registration(
            {"registryHelper": self.registry_helper, "queryScript": self.query_script},
            app,
            path,
            [],
        )


def inspect_live(native: Native, app: dict, path: Path) -> tuple[dict, list[dict]]:
    """Bracket bundle inspection with process identities to catch exec/PID reuse.

    Returns:
        The validated operation result.

    """
    running = native.running(app)
    before = {item["pid"]: native.process(item["pid"]) for item in running}
    disk = native.inspect(path, app)
    for item in running:
        pid = item["pid"]
        if (
            Path(item["path"]) != path
            or before[pid][0] not in disk["uuids"]
            or before[pid][3] not in disk["cdhashes"]
            or native.process(pid) != before[pid]
        ):
            fail(
                f"{app['bundle']}: running/disk identity mismatch (PID {pid}); fully Quit and reopen the canonical app"
            )
    if native.running(app) != running:
        fail("Application lifecycle changed during inspection; retry")
    return disk, [dict(item, identity=before[item["pid"]]) for item in running]


def validate_upgrade(disk: dict, source: dict) -> None:
    """Reject unknown version ordering and silent vendor-build downgrades."""
    if disk == source:
        return
    old, new = disk["build"], source["build"]
    if not re.fullmatch(r"\d+(?:\.\d+)*", old) or not re.fullmatch(
        r"\d+(?:\.\d+)*", new
    ):
        fail("Cannot order application builds; refusing an unverified replacement")
    if tuple(map(int, new.split("."))) < tuple(map(int, old.split("."))):
        fail(f"Refusing app downgrade {old} -> {new}; update the Nix package selection")


def previous_paths(app: dict, apps_dir: Path) -> list[Path]:
    """Confine explicitly retired names to this application's canonical directory.

    Returns:
        Distinct previous bundle paths, never arbitrary source/backup locations.

    """
    names = app.get("previousBundles", [])
    if not isinstance(names, list) or any(
        not isinstance(name, str) or not re.fullmatch(r"[^/]+\.app", name)
        for name in names
    ):
        fail("Invalid previous application bundle names")
    folded = [app["bundle"].casefold(), *(name.casefold() for name in names)]
    if len(folded) != len(set(folded)):
        fail("Ambiguous previous application bundle names")
    return [apps_dir / name for name in names]


def previous_identities(
    native: Native, app: dict, apps_dir: Path, source: dict
) -> dict[Path, dict]:
    """Verify legacy copies before retirement, and require the entire app quit.

    Returns:
        Complete signed legacy identities to preserve in the transaction.

    """
    found = {}
    for path in previous_paths(app, apps_dir):
        if path.is_symlink():
            fail(f"Previous protected app must be a real copied bundle: {path}")
        if path.exists():
            found[path] = native.inspect(path, app)
            validate_upgrade(found[path], source)
    if found and native.running(app):
        fail(f"Quit {app['bundle']} before migrating its canonical pathname")
    return found


def preflight(native: Native, app: dict, apps_dir: Path) -> tuple[dict, dict | None]:
    """Block upgrades of running apps and silent downgrades, allow true no-ops.

    Returns:
        The validated operation result.

    """
    source = native.inspect(Path(app["source"]), app)
    previous_identities(native, app, apps_dir, source)
    installed = apps_dir / app["bundle"]
    if installed.is_symlink():
        fail(f"Protected app must be a real copied bundle: {installed}")
    if not installed.exists():
        if native.running(app):
            fail("Protected app is running from another path; Quit it first")
        return source, None
    disk, running = inspect_live(native, app, installed)
    if disk != source:
        if running:
            fail(
                f"Quit {app['bundle']} before activating an update; installed app was left intact"
            )
        validate_upgrade(disk, source)
    return source, disk


def transaction_status(transaction: Path, status: str, paths: dict) -> None:
    """Record mutation intent atomically before moving any complete bundle."""
    descriptor, name = tempfile.mkstemp(prefix=".journal-", dir=transaction)
    try:
        with os.fdopen(descriptor, "w") as stream:
            json.dump({"status": status, **paths}, stream, sort_keys=True)
            stream.flush()
            os.fsync(stream.fileno())
        Path(name).replace(transaction / "transaction.json")
        parent = os.open(transaction, os.O_RDONLY)
        try:
            os.fsync(parent)
        finally:
            os.close(parent)
    finally:
        Path(name).unlink(missing_ok=True)


@dataclass
class AppTransaction:
    """Keep recovery intent beside complete retained bundles."""

    directory: Path
    app: dict
    apps_dir: Path
    source: dict
    disk: dict | None
    previous: dict[Path, dict]
    retained: bool = False

    def status(self, status: str, **extra: str) -> None:
        """Persist selected identities and every mutation intent."""
        transaction_status(
            self.directory,
            status,
            {
                "canonical": str(self.apps_dir / self.app["bundle"]),
                "selectedSource": self.app["source"],
                "sourceIdentity": self.source,
                "previous": {
                    str(path): identity for path, identity in self.previous.items()
                },
                **extra,
            },
        )

    def stage(self, native: Native) -> None:
        """Verify a private copy and unchanged lifecycle before installation."""
        staged = self.directory / self.app["bundle"]
        if self.source != self.disk:
            native.copy(Path(self.app["source"]), staged)
            if native.inspect(staged, self.app) != self.source:
                fail("Staged signature differs from the selected package")
        if (
            preflight(native, self.app, self.apps_dir) != (self.source, self.disk)
            or previous_identities(native, self.app, self.apps_dir, self.source)
            != self.previous
        ):
            fail("Application changed while staging; original retained")
        if self.source != self.disk:
            # Keep recovery material even if a mutation succeeds and its caller
            # fails before observing success, or a journal write fails.
            self.retained = True
            self.status("install-intent")
            native.swap(staged, self.apps_dir / self.app["bundle"])
            if self.disk is not None:
                if native.inspect(staged, self.app) != self.disk:
                    fail("Retained prior application identity changed")
                native.unregister(staged, self.app)
            self.status("installed")

    def retire(self, native: Native) -> None:
        """Retain verified old pathnames and retire their precise registry URLs."""
        for path, identity in self.previous.items():
            if native.running(self.app):
                fail("Application launched during migration; Quit it before retrying")
            if path.is_symlink() or native.inspect(path, self.app) != identity:
                fail("Previous application changed during migration")
            self.retained = True
            self.status("retire-intent", retiring=str(path))
            backup = self.directory / path.name
            native.move(path, backup)
            if native.inspect(backup, self.app) != identity:
                fail("Retained previous application identity changed")
            # Launch Services can follow a moved inode; .noindex alone is not
            # registration exclusion. Retire only these verified URLs.
            native.unregister(path, self.app)
            native.unregister(backup, self.app)
            self.status("retired", retired=str(path))


def install(native: Native, app: dict, apps_dir: Path) -> str:
    """Stage and verify before a final live check and atomic commit.

    Returns:
        The validated operation result.

    Raises:
        LifecycleError: Identity changed or mutation needs inspected recovery.
        OSError: Staging failed before any canonical mutation was attempted.
        subprocess.SubprocessError: A native tool failed before mutation.

    """
    source, disk = preflight(native, app, apps_dir)
    previous = previous_identities(native, app, apps_dir, source)
    if source == disk and not previous:
        return "unchanged"
    transaction = AppTransaction(
        Path(
            tempfile.mkdtemp(
                prefix=".hm-app-update-", suffix=".noindex", dir=apps_dir.parent
            )
        ),
        app,
        apps_dir,
        source,
        disk,
        previous,
    )
    try:
        transaction.stage(native)
        transaction.retire(native)
        native.register(apps_dir / app["bundle"])
        transaction.status("registered-user")
    except (LifecycleError, OSError, subprocess.SubprocessError) as error:
        if transaction.retained:
            fail(
                f"{error}; complete bundles and journal retained in {transaction.directory}"
            )
        raise
    else:
        return f"installed; previous bundle retained in {transaction.directory}"
    finally:
        if not transaction.retained:
            shutil.rmtree(transaction.directory)


@contextmanager
def private_lock(state: Path) -> Generator[None]:
    """Reject redirected state/locks instead of modifying arbitrary targets."""
    state.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = state.lstat()
    if (
        not stat.S_ISDIR(info.st_mode)
        or info.st_uid != os.getuid()
        or info.st_mode & 0o077
    ):
        fail("Lifecycle state must be a private, owned real directory")
    descriptor = os.open(
        state / "lifecycle.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600
    )
    try:
        info = os.fstat(descriptor)
        if (
            not stat.S_ISREG(info.st_mode)
            or info.st_uid != os.getuid()
            or info.st_mode & 0o077
        ):
            fail("Unsafe lifecycle lock")
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield
    finally:
        os.close(descriptor)


def execute(manifest: dict, mode: str) -> dict:
    """Inspect every protected app, or perform its guarded transaction.

    Returns:
        The health report; authorization remains unknown.

    """
    native = Native(
        manifest["queryScript"], manifest["rsync"], manifest.get("registryHelper", "")
    )
    results = []
    for app in manifest["apps"]:
        path = Path(manifest["appsDirectory"]) / app["bundle"]
        runtime = {}
        if mode == "preflight":
            preflight(native, app, path.parent)
            result = "safe"
        elif mode == "install":
            result = install(native, app, path.parent)
        else:
            source = native.inspect(Path(app["source"]), app)
            if previous_identities(native, app, path.parent, source):
                fail(
                    "Previous canonical application remains; guarded migration required"
                )
            disk, running = inspect_live(native, app, path)
            if source != disk:
                fail(
                    f"{app['bundle']}: installed identity differs from Nix; activation required"
                )
            runtime = {"running": running}
            result = "ready" if running else "not-running"
            if mode == "refresh":
                native.register(path)
        results.append({"bundle": app["bundle"], "status": result, **runtime})
    return {"status": "ok", "apps": results, "authorization": "unknown"}


def refresh_status(state: Path, report: dict) -> None:
    """Atomically retain the current monitor result and notify new failures."""
    target = state / "status.json"
    previous = (
        target.read_text() if target.is_file() and not target.is_symlink() else ""
    )
    value = json.dumps(report, sort_keys=True) + "\n"
    if previous == value:
        return
    descriptor, name = tempfile.mkstemp(dir=state, prefix=".status-")
    try:
        with os.fdopen(descriptor, "w") as stream:
            stream.write(value)
        Path(name).replace(target)
    finally:
        Path(name).unlink(missing_ok=True)
    if report["status"] == "blocked" and previous != value:
        # Notification delivery is best effort; status.json and --check are the
        # authoritative health surfaces even when notifications are disabled.
        with suppress(LifecycleError, OSError, subprocess.SubprocessError):
            command(
                "/usr/bin/osascript",
                "-e",
                'display notification "Run hm-macos-applications --check for details." with title "Managed application needs attention"',
            )


def perform(manifest: dict, mode: str) -> dict:
    """Serialize mutations; check and preflight do not create state.

    Returns:
        The complete report, including actionable monitor failures.

    Raises:
        LifecycleError: If an explicit operation cannot safely proceed.
        OSError: If a native or state operation fails.
        ValueError: If native metadata cannot be parsed.
        KeyError: If generated configuration is incomplete.
        subprocess.SubprocessError: If native inspection times out.

    """
    state = Path(manifest["stateDirectory"])
    with (
        private_lock(state)
        if mode in {"install", "refresh", "observe"}
        else nullcontext()
    ):
        try:
            report = execute(manifest, mode)
        except (
            LifecycleError,
            OSError,
            ValueError,
            KeyError,
            subprocess.SubprocessError,
        ) as error:
            if mode not in {"refresh", "observe"}:
                raise
            report = {
                "status": "blocked",
                "error": str(error),
                "authorization": "unknown",
            }
        if mode in {"refresh", "observe"}:
            refresh_status(state, report)
        return report


def refresh_system(
    manifest: dict,
    manifest_path: Path,
    *,
    if_changed: bool = False,
    state: Path = ROOT_STATE,
) -> dict:
    """Refresh verified bundles once per runtime identity, in both registries.

    The launchd watch is only a signal. No user-written status is read here.
    Root independently verifies paths and signatures before registering them.

    Returns:
        Registration results, without claiming a privacy grant.

    """
    if os.geteuid() != 0:
        fail(
            "System registration refresh requires root; use the Darwin activation hook"
        )
    with private_lock(state):
        return refresh_system_locked(
            manifest, manifest_path, state, if_changed=if_changed
        )


def registered_paths(manifest: dict, app: dict, prefix: list[str]) -> set[Path]:
    """Query eligible native URLs without reading mutable user status or journals.

    Returns:
        Available URLs with explicit store/recovery tombstones removed.

    """
    value = json.loads(
        command(
            *prefix,
            manifest["registryHelper"],
            "--query-script",
            manifest["queryScript"],
            "--registered-paths",
            app["bundleId"],
        )
    )
    paths = value.get(app["bundleId"]) if isinstance(value, dict) else None
    if not isinstance(paths, list) or not all(isinstance(path, str) for path in paths):
        fail("Invalid native registration inventory")
    if any(
        not Path(path).is_absolute()
        or ".." in Path(path).parts
        or str(Path(path)) != path
        for path in paths
    ):
        fail("Noncanonical native registration path")
    return {Path(path) for path in paths}


def unregister_registration(
    manifest: dict, app: dict, path: Path, prefix: list[str]
) -> None:
    """Unregister only an eligible URL, then independently verify its retirement.

    Launch Services returns a scan error for unregistered hidden backups. Query
    first rather than swallowing that error or registering a backup to remove it.
    """
    if path not in registered_paths(manifest, app, prefix):
        return
    command(*prefix, LSREGISTER, "-u", str(path))
    if path in registered_paths(manifest, app, prefix):
        fail(f"Application registration remains eligible after retirement: {path}")


def owned_recovery_url(path: Path, canonical: Path, app: dict) -> bool:
    """Limit backup cleanup to known names beside the selected copied-app tree.

    Returns:
        Whether the URL is a narrowly scoped protected-app recovery location.

    """
    return (
        path.parent.parent == canonical.parent.parent
        and path.parent.name.startswith(".hm-app-update-")
        and path.parent.name.endswith(".noindex")
        and path.name in {app["bundle"], *app.get("previousBundles", [])}
    )


def retirable_registrations(
    native: Native, manifest: dict, app: dict, prefix: list[str]
) -> set[Path]:
    """Validate the complete root/user cleanup plan before any registry mutation.

    Returns:
        Only known previous names, verified store bundles and scoped backups.

    """
    path = Path(manifest["appsDirectory"]) / app["bundle"]
    previous = set(previous_paths(app, path.parent))
    available = registered_paths(manifest, app, []) | registered_paths(
        manifest, app, prefix
    )
    retiring = (available | previous) - {path}
    for candidate in retiring:
        scoped = (
            candidate in previous
            or re.fullmatch(r"/nix/store/[^/]+/Applications/[^/]+\.app", str(candidate))
            or owned_recovery_url(candidate, path, app)
        )
        if not scoped:
            fail(f"Competing application registration requires inspection: {candidate}")
        if candidate.is_symlink():
            fail(f"Refusing registration cleanup through a symlink: {candidate}")
        if owned_recovery_url(candidate, path, app) and candidate.parent.is_symlink():
            fail(
                "Refusing registration cleanup through a redirected recovery directory"
            )
        if candidate.exists():
            # The mutable record chooses no privileged action by itself: each
            # existing bundle must independently pass the vendor signature guard.
            native.inspect(candidate, app)
    return retiring


def reconcile_system_registration(
    native: Native, manifest: dict, app: dict, prefix: list[str]
) -> None:
    """Retire verified competing store/backups and prove root/user resolution."""
    path = Path(manifest["appsDirectory"]) / app["bundle"]
    for candidate in sorted(retirable_registrations(native, manifest, app, prefix)):
        native.unregister(candidate, app)
        unregister_registration(manifest, app, candidate, prefix)
    native.register(path)
    command(*prefix, LSREGISTER, "-f", str(path))
    if registered_paths(manifest, app, []) != {path} or registered_paths(
        manifest, app, prefix
    ) != {path}:
        fail("Canonical registration could not be established in both contexts")


def refresh_system_locked(
    manifest: dict, manifest_path: Path, state: Path, *, if_changed: bool
) -> dict:
    """Inspect fresh user runtime state under the root-owned serialization lock.

    Returns:
        The independently verified registration result.

    """
    user = manifest["username"]
    uid = pwd.getpwnam(user).pw_uid
    prefix = [
        "/bin/launchctl",
        "asuser",
        str(uid),
        "/usr/bin/sudo",
        "--user=" + user,
        "--",
    ]
    # The logged-in user sees GUI processes that root's NSWorkspace may omit.
    report = json.loads(
        command(
            *prefix,
            sys.executable,
            str(Path(__file__)),
            "--manifest",
            str(manifest_path),
            "--mode",
            "check",
        )
    )
    if report.get("status") != "ok":
        fail("User-context identity inspection failed")
    native = Native(
        manifest["queryScript"], manifest["rsync"], manifest["registryHelper"]
    )
    verified = []
    for app in manifest["apps"]:
        path = Path(manifest["appsDirectory"]) / app["bundle"]
        identity = native.inspect(path, app)
        if path.is_symlink() or identity != native.inspect(Path(app["source"]), app):
            fail(
                "Refusing system registration of a bundle that differs from the selected verified source"
            )
        verified.append({
            "path": str(path),
            "source": app["source"],
            "identity": identity,
            "previous": [
                str(previous) for previous in previous_paths(app, path.parent)
            ],
        })
    fingerprint = (
        json.dumps({"verified": verified, "runtime": report}, sort_keys=True) + "\n"
    )
    ledger = state / "registered.json"
    if if_changed and ledger.is_file() and ledger.read_text() == fingerprint:
        return {"status": "ok", "registration": "current", "authorization": "unknown"}
    results = []
    for app in manifest["apps"]:
        path = Path(manifest["appsDirectory"]) / app["bundle"]
        reconcile_system_registration(native, manifest, app, prefix)
        results.append({
            "bundle": app["bundle"],
            "status": "registered-system-and-user",
        })
    # Commit only after both registries succeeded. A failed attempt remains retryable.
    descriptor, name = tempfile.mkstemp(dir=state, prefix=".registered-")
    try:
        with os.fdopen(descriptor, "w") as stream:
            stream.write(fingerprint)
        Path(name).replace(ledger)
    finally:
        Path(name).unlink(missing_ok=True)
    return {"status": "ok", "apps": results, "authorization": "unknown"}


def main() -> int:
    """Run the configured lifecycle operation.

    Returns:
        Zero for healthy state, one for an actionable failure.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument(
        "--mode",
        choices=[
            "preflight",
            "install",
            "check",
            "refresh",
            "refresh-system",
            "observe",
        ],
        default="check",
    )
    parser.add_argument("--if-changed", action="store_true")
    args = parser.parse_args()
    if args.if_changed and args.mode != "refresh-system":
        parser.error("--if-changed requires --mode refresh-system")
    try:
        manifest = json.loads(args.manifest.read_text())
        report = (
            refresh_system(manifest, args.manifest, if_changed=args.if_changed)
            if args.mode == "refresh-system"
            else perform(manifest, args.mode)
        )
    except (
        LifecycleError,
        OSError,
        ValueError,
        KeyError,
        subprocess.SubprocessError,
    ) as error:
        report = {"status": "blocked", "error": str(error), "authorization": "unknown"}
    sys.stdout.write(json.dumps(report) + "\n")
    return 0 if report["status"] == "ok" else 1


if __name__ == "__main__":
    sys.exit(main())
