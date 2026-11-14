"""Exercise protected copy safety, recovery, and loaded-image comparisons."""

from __future__ import annotations

import importlib.util
import json
import os
import plistlib
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Native fixture processes.
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

SPEC = importlib.util.spec_from_file_location(
    "application_lifecycle",
    Path(__file__).parents[2] / "modules/home/macos/application_lifecycle.py",
)
assert SPEC
assert SPEC.loader
manager = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = manager
SPEC.loader.exec_module(manager)

PUBLIC_DIRECTORY_MODE = 0o755
UUID_TEXT_LENGTH = 36
MAX_SIGNATURE_SECONDS = 120

APP = {
    "bundle": "Example.app",
    "bundleId": "org.example.app",
    "teamId": "VENDOR",
    "source": "/selected/Example.app",
}
OLD = {"cdhashes": ["old"], "build": "10", "uuids": ["OLD"]}
NEW = {"cdhashes": ["new"], "build": "11", "uuids": ["NEW"]}


class FixtureNative:
    """Model the native boundary without touching host applications."""

    def __init__(
        self, source: dict = NEW, disk: dict = OLD, *, running: bool = False
    ) -> None:
        """Init  ."""
        self.source = source
        self.disk = disk
        self.live = [{"pid": 42, "path": ""}] if running else []
        self.loaded = "OLD"
        self.retained = None
        self.calls = []

    def inspect(self, path: Path, _app: dict) -> dict:
        """Return the fixture bundle identity.

        Returns:
            The selected fixture identity.

        """
        if str(path) == APP["source"]:
            return self.source
        if ".noindex" in str(path):
            return self.source if self.retained is None else self.retained
        return self.disk

    def running(self, _app: dict) -> list[dict]:
        """Return the controlled running inventory.

        Returns:
            A copy of the fixture inventory.

        """
        return self.live.copy()

    def process(self, _pid: int) -> tuple[str, int, int, str]:
        """Return the loaded fixture image.

        Returns:
            Its UUID and process generation.

        """
        return self.loaded, 100, 1, "old"

    def copy(self, _source: Path, target: Path) -> None:
        """Copy."""
        self.calls.append("copy")
        target.mkdir()

    def swap(self, _staged: Path, _installed: Path) -> None:
        """Swap."""
        self.calls.append("swap")
        self.retained = self.disk
        self.disk = self.source

    def register(self, _path: Path) -> None:
        """Register."""
        self.calls.append("register")

    def unregister(self, _path: Path, _app: dict) -> None:
        """Retire the complete retained fixture's URL."""
        self.calls.append("unregister")


def fixture(
    tmp_path: Path, source: dict = NEW, disk: dict = OLD, *, running: bool = False
) -> tuple[FixtureNative, Path]:
    """Create an isolated installed bundle.

    Returns:
        The native boundary and copied apps directory.

    """
    directory = tmp_path / "Apps"
    directory.mkdir()
    (directory / APP["bundle"]).mkdir()
    native = FixtureNative(source=source, disk=disk, running=running)
    if native.live:
        native.live[0]["path"] = str(directory / APP["bundle"])
    return native, directory


def test_running_upgrade_is_rejected_without_copy(tmp_path: Path) -> None:
    """Running upgrade is rejected without copy."""
    native, directory = fixture(tmp_path, running=True)
    with pytest.raises(manager.LifecycleError, match="Quit"):
        manager.install(native, APP, directory)
    assert native.calls == []


def test_running_noop_does_not_touch_app(tmp_path: Path) -> None:
    """Running noop does not touch app."""
    native, directory = fixture(tmp_path, source=OLD, running=True)
    assert manager.install(native, APP, directory) == "unchanged"
    assert native.calls == []


def test_quit_upgrade_verifies_stages_and_swaps(tmp_path: Path) -> None:
    """Quit upgrade verifies stages and swaps."""
    native, directory = fixture(tmp_path)
    assert "retained" in manager.install(native, APP, directory)
    assert native.calls == ["copy", "swap", "unregister", "register"]


def test_downgrade_rejected(tmp_path: Path) -> None:
    """Downgrade rejected."""
    native, directory = fixture(tmp_path, source=OLD, disk=NEW)
    with pytest.raises(manager.LifecycleError, match="downgrade"):
        manager.install(native, APP, directory)
    assert native.calls == []


@pytest.mark.parametrize("build", ["", "future-preview"])
def test_unknown_build_order_rejected(tmp_path: Path, build: str) -> None:
    """Unknown build order rejected."""
    native, directory = fixture(tmp_path, source=NEW | {"build": build})
    with pytest.raises(manager.LifecycleError, match="order"):
        manager.install(native, APP, directory)


def test_same_version_different_signature_is_upgrade(tmp_path: Path) -> None:
    """Same version different signature is upgrade."""
    native, directory = fixture(tmp_path, source=NEW | {"build": "10"}, running=True)
    with pytest.raises(manager.LifecycleError, match="Quit"):
        manager.install(native, APP, directory)


def test_loaded_image_mismatch_detected(tmp_path: Path) -> None:
    """Loaded image mismatch detected."""
    native, directory = fixture(tmp_path, disk=NEW, source=NEW, running=True)
    with pytest.raises(manager.LifecycleError, match="identity mismatch"):
        manager.preflight(native, APP, directory)


def test_process_reuse_detected(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Process reuse detected."""
    native, directory = fixture(tmp_path, source=OLD, running=True)
    values = iter([("OLD", 100, 1, "old"), ("OLD", 101, 2, "old")])
    monkeypatch.setattr(native, "process", lambda _: next(values))
    with pytest.raises(manager.LifecycleError, match="mismatch"):
        manager.preflight(native, APP, directory)


def test_launch_during_staging_retains_original(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Launch during staging retains original."""
    native, directory = fixture(tmp_path)
    original = native.copy

    def copy(source: Path, target: Path) -> None:
        """Copy."""
        original(source, target)
        native.live = [{"pid": 42, "path": str(directory / APP["bundle"])}]

    monkeypatch.setattr(native, "copy", copy)
    with pytest.raises(manager.LifecycleError, match="Quit"):
        manager.install(native, APP, directory)
    assert native.calls == ["copy"]
    assert not list(tmp_path.glob(".hm-app-update-*"))
    assert native.disk == OLD


def test_last_instant_launch_detected_after_atomic_swap(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Last instant launch detected after atomic swap."""
    native, directory = fixture(tmp_path)
    original = native.swap

    def swap(staged: Path, installed: Path) -> None:
        """Swap."""
        native.live = [{"pid": 42, "path": str(installed)}]
        original(staged, installed)

    monkeypatch.setattr(native, "swap", swap)
    manager.install(native, APP, directory)
    with pytest.raises(manager.LifecycleError, match="mismatch"):
        manager.inspect_live(native, APP, directory / APP["bundle"])


def test_failed_staging_never_swaps(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Failed staging never swaps."""
    native, directory = fixture(tmp_path)

    def fail(_source: Path, target: Path) -> None:
        """Reject the fixture copy.

        Raises:
            OSError: For the simulated write failure.

        """
        target.mkdir()
        message = "fixture copy failure"
        raise OSError(message)

    monkeypatch.setattr(native, "copy", fail)
    with pytest.raises(OSError, match="fixture"):
        manager.install(native, APP, directory)
    assert native.calls == []
    assert not list(tmp_path.glob(".hm-app-update-*"))


def test_state_symlink_rejected_without_chmod(tmp_path: Path) -> None:
    """State symlink rejected without chmod."""
    real = tmp_path / "real"
    real.mkdir(mode=PUBLIC_DIRECTORY_MODE)
    link = tmp_path / "state"
    link.symlink_to(real, target_is_directory=True)
    with (
        pytest.raises(manager.LifecycleError, match="private"),
        manager.private_lock(link),
    ):
        pass
    assert real.stat().st_mode & 0o777 == PUBLIC_DIRECTORY_MODE


def test_lock_symlink_rejected(tmp_path: Path) -> None:
    """Lock symlink rejected."""
    state = tmp_path / "state"
    state.mkdir(mode=0o700)
    victim = tmp_path / "victim"
    victim.write_text("unchanged")
    (state / "lifecycle.lock").symlink_to(victim)
    with (
        pytest.raises(OSError, match=r"symbolic links|levels of symbolic"),
        manager.private_lock(state),
    ):
        pass
    assert victim.read_text() == "unchanged"


@pytest.mark.skipif(
    sys.platform != "darwin", reason="Native libproc and rename exchange"
)
def test_native_process_identity_and_atomic_exchange(tmp_path: Path) -> None:
    """Native process identity and atomic exchange."""
    loaded, unique, _, digest = manager.process_identity(os.getpid())
    assert len(loaded) == UUID_TEXT_LENGTH
    assert unique > 0
    assert len(digest) == manager.CDHASH_SIZE * 2
    staged = tmp_path / "staged.app"
    installed = tmp_path / "installed.app"
    staged.mkdir()
    installed.mkdir()
    (staged / "version").write_text("new")
    (installed / "version").write_text("old")
    manager.Native("", "").swap(staged, installed)
    assert (installed / "version").read_text() == "new"
    assert (staged / "version").read_text() == "old"


@pytest.mark.nix_integration
@pytest.mark.skipif(sys.platform != "darwin", reason="Native signed Mach-O fixtures")
def test_native_signed_update_and_running_image_mismatch(tmp_path: Path) -> None:
    """Verify real signed staging, no-op, running refusal, and loaded UUID drift."""

    def make_app(directory: Path, build: int) -> Path:
        """Build an isolated signed fixture.

        Returns:
            The application bundle.

        """
        path = directory / "Example.app"
        contents = path / "Contents"
        binary = contents / "MacOS/example"
        binary.parent.mkdir(parents=True)
        (contents / "Info.plist").write_bytes(
            plistlib.dumps({
                "CFBundleIdentifier": "org.example.lifecycle-fixture",
                "CFBundleExecutable": "example",
                "CFBundleVersion": str(build),
                "CFBundlePackageType": "APPL",
            })
        )
        manager.command(
            "/usr/bin/clang",
            "-x",
            "c",
            "-o",
            str(binary),
            "-DVERSION=1",
            str(Path(__file__).with_name("lifecycle-fixture.c")),
        )
        (contents / "Resources").mkdir()
        (contents / "Resources/payload").write_text(str(build))
        manager.command("/usr/bin/codesign", "--force", "--sign", "-", str(path))
        return path

    old = make_app(tmp_path / "old", 1)
    new = make_app(tmp_path / "new", 2)
    apps = tmp_path / "Apps"
    apps.mkdir()
    app = {
        "bundle": "Example.app",
        "bundleId": "org.example.lifecycle-fixture",
        "teamId": "not set",
        "source": str(old),
    }

    class NativeFixture(manager.Native):
        """Use actual code signing/libproc with a controlled process inventory."""

        def __init__(self, query_script: str, rsync: str) -> None:
            """Set isolated fixture state."""
            super().__init__(query_script, rsync)
            self.live: list[dict] = []

        def running(self, _app: dict) -> list[dict]:
            """Return the native fixture's process inventory.

            Returns:
                The live fixture process.

            """
            return self.live

        @staticmethod
        def register(_path: Path) -> None:
            """Keep disposable fixtures out of the user's Launch Services registry."""

        @staticmethod
        def unregister(_path: Path, _app: dict) -> None:
            """Keep isolated signing fixtures out of native registration mutations."""

    native = NativeFixture("", "/usr/bin/rsync")
    assert "installed" in manager.install(native, app, apps)
    installed = apps / "Example.app"
    old_identity = native.inspect(installed, app)
    with subprocess.Popen([str(installed / "Contents/MacOS/example")]) as process:  # ruff: ignore[subprocess-without-shell-equals-true] - Isolated fixture executable.
        try:
            native.live = [{"pid": process.pid, "path": str(installed)}]
            assert manager.install(native, app, apps) == "unchanged"
            updated = app | {"source": str(new)}
            with pytest.raises(manager.LifecycleError, match="Quit"):
                manager.install(native, updated, apps)
            assert native.inspect(installed, app) == old_identity
            staged = tmp_path / "swap.app"
            native.copy(new, staged)
            native.swap(staged, installed)
            # Red control: a complete replaced app passes signing, yet the live
            # loaded image still belongs to the prior bundle. Disk-only is wrong.
            assert native.inspect(installed, app) != old_identity
            assert native.inspect(installed, app)["uuids"] == old_identity["uuids"]
            assert manager.process_identity(process.pid)[0] in old_identity["uuids"]
            with pytest.raises(manager.LifecycleError, match="identity mismatch"):
                manager.inspect_live(native, app, installed)
        finally:
            process.terminate()
            process.wait()
    native.live = []
    assert manager.preflight(native, updated, apps)[0] == native.inspect(
        installed, updated
    )


@pytest.mark.skipif(sys.platform != "darwin", reason="Native rsync exclusion")
def test_native_rsync_exclusion_preserves_protected_bundle(tmp_path: Path) -> None:
    """Copy ordinary apps and delete obsolete ones without touching protected bytes."""
    source = tmp_path / "source"
    target = tmp_path / "target"
    source.mkdir()
    target.mkdir()
    (source / "Example.app").mkdir()
    (source / "Example.app/version").write_text("replacement")
    (source / "Ordinary.app").mkdir()
    (source / "Ordinary.app/version").write_text("new")
    (target / "Example.app").mkdir()
    protected = target / "Example.app/version"
    protected.write_text("running")
    inode = protected.stat().st_ino
    (target / "Obsolete.app").mkdir()
    manager.command(
        "/usr/bin/rsync",
        "--recursive",
        "--delete",
        "--exclude=/Example.app",
        str(source) + "/",
        str(target) + "/",
    )
    assert protected.read_text() == "running"
    assert protected.stat().st_ino == inode
    assert (target / "Ordinary.app/version").read_text() == "new"
    assert not (target / "Obsolete.app").exists()


def test_resource_only_update_detected_with_unchanged_uuid(tmp_path: Path) -> None:
    """Reject live signing drift even when the main executable UUID is unchanged."""
    identity = NEW | {"uuids": ["OLD"]}
    native, directory = fixture(tmp_path, source=identity, disk=identity, running=True)
    with pytest.raises(manager.LifecycleError, match="identity mismatch"):
        manager.inspect_live(native, APP, directory / APP["bundle"])


def test_system_refresh_requires_root(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Reject an unprivileged system refresh before reading mutable metadata."""
    monkeypatch.setattr(manager.os, "geteuid", lambda: 501)
    with pytest.raises(manager.LifecycleError, match="requires root"):
        manager.refresh_system({}, tmp_path / "manifest")


@pytest.mark.parametrize("matching", [True, False])
def test_system_refresh_verifies_then_orders_root_and_user(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, *, matching: bool
) -> None:
    """Require a source match and preserve the tested root-then-user sequence."""
    native, directory = fixture(tmp_path, source=NEW, disk=NEW if matching else OLD)
    operations = []
    monkeypatch.setattr(manager.os, "geteuid", lambda: 0)
    monkeypatch.setattr(manager.pwd, "getpwnam", lambda _: SimpleNamespace(pw_uid=501))
    monkeypatch.setattr(manager, "Native", lambda *_: native)
    monkeypatch.setattr(native, "register", lambda _: operations.append("root"))

    def command(*args: str) -> str:
        """Record scoped native calls.

        Returns:
            A successful command result.

        """
        if "--registered-paths" in args:
            return json.dumps({APP["bundleId"]: [str(directory / APP["bundle"])]})
        assert args[:6] == (
            "/bin/launchctl",
            "asuser",
            "501",
            "/usr/bin/sudo",
            "--user=fixture",
            "--",
        )
        operations.append("user-check" if args[-1] == "check" else "user-register")
        return json.dumps({"status": "ok", "apps": [{"pid": 123}]})

    monkeypatch.setattr(manager, "command", command)
    manifest = {
        "username": "fixture",
        "queryScript": "query",
        "rsync": "rsync",
        "registryHelper": "registry-query",
        "appsDirectory": str(directory),
        "apps": [APP],
    }
    if matching:
        assert (
            manager.refresh_system(
                manifest, tmp_path / "manifest", state=tmp_path / "root-state"
            )["status"]
            == "ok"
        )
        assert operations == ["user-check", "root", "user-register"]
    else:
        with pytest.raises(manager.LifecycleError, match="differs"):
            manager.refresh_system(
                manifest, tmp_path / "manifest", state=tmp_path / "root-state"
            )
        assert operations == ["user-check"]


def test_observe_records_health_without_registration_writes(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Observe events without re-registering an unchanged healthy application."""
    native, directory = fixture(tmp_path, source=OLD)
    state = tmp_path / "state"
    manifest = tmp_path / "manifest.json"
    manifest.write_text(
        json.dumps({
            "queryScript": "query",
            "rsync": "rsync",
            "appsDirectory": str(directory),
            "stateDirectory": str(state),
            "apps": [APP],
        })
    )
    monkeypatch.setattr(manager, "Native", lambda *_: native)
    monkeypatch.setattr(
        manager.sys,
        "argv",
        ["lifecycle", "--manifest", str(manifest), "--mode", "observe"],
    )
    assert manager.main() == 0
    assert json.loads((state / "status.json").read_text())["status"] == "ok"
    assert native.calls == []


def test_system_refresh_deduplicates_live_incarnations(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Repeated wakeups do not rewrite registration; a new process does."""
    native, directory = fixture(tmp_path, source=NEW, disk=NEW)
    monkeypatch.setattr(manager.os, "geteuid", lambda: 0)
    monkeypatch.setattr(manager.pwd, "getpwnam", lambda _: SimpleNamespace(pw_uid=501))
    monkeypatch.setattr(manager, "Native", lambda *_: native)
    runtime = {
        "status": "ok",
        "apps": [{"pid": 123, "identity": ["uuid", 99, 1, "hash"]}],
    }
    registrations = []
    monkeypatch.setattr(native, "register", lambda _: registrations.append("root"))
    broken = False

    def run(*args: str) -> str:
        """Model fresh runtime queries and a failed user registration.

        Returns:
            Fresh inspection JSON, or successful registration output.

        """
        if "--registered-paths" in args:
            return json.dumps({APP["bundleId"]: [str(directory / APP["bundle"])]})
        if args[-1] == "check":
            return json.dumps(runtime)
        registrations.append("user")
        if broken:
            manager.fail("registration failed")
        return ""

    monkeypatch.setattr(manager, "command", run)
    manifest = {
        "username": "fixture",
        "queryScript": "query",
        "rsync": "rsync",
        "registryHelper": "registry-query",
        "appsDirectory": str(directory),
        "apps": [APP],
    }
    state = tmp_path / "root-state"
    manager.refresh_system(
        manifest, tmp_path / "manifest", state=state, if_changed=True
    )
    manager.refresh_system(
        manifest, tmp_path / "manifest", state=state, if_changed=True
    )
    assert registrations == ["root", "user"]
    runtime["apps"][0]["identity"][1] = 100
    broken = True
    with pytest.raises(manager.LifecycleError, match="registration failed"):
        manager.refresh_system(
            manifest, tmp_path / "manifest", state=state, if_changed=True
        )
    broken = False
    manager.refresh_system(
        manifest, tmp_path / "manifest", state=state, if_changed=True
    )
    assert registrations == ["root", "user"] * 3
    manager.refresh_system(
        manifest, tmp_path / "manifest", state=state, if_changed=True
    )
    assert registrations == ["root", "user"] * 3


def test_observer_status_changes_only_for_new_state(tmp_path: Path) -> None:
    """Avoid registration feedback while retaining coalesced process changes."""
    report = {
        "status": "ok",
        "apps": [{"running": [{"pid": 1, "identity": ["uuid", 42]}]}],
    }
    manager.refresh_status(tmp_path, report)
    target = tmp_path / "status.json"
    first = target.stat().st_ino
    manager.refresh_status(tmp_path, report)
    assert target.stat().st_ino == first
    report["apps"][0]["running"][0]["identity"][1] = 43
    manager.refresh_status(tmp_path, report)
    assert json.loads(target.read_text()) == report
    assert target.stat().st_ino != first


@pytest.mark.parametrize(
    ("args", "duration"),
    [
        (("/usr/bin/codesign", "--verify", "fixture.app"), 45),
        (("/usr/bin/codesign", "-d", "--verbose=4", "fixture.app"), 45),
        (("/bin/launchctl", "asuser", "501", "helper", "--mode", "check"), 150),
    ],
)
def test_slow_healthy_native_inspection(
    monkeypatch: pytest.MonkeyPatch, args: tuple[str, ...], duration: int
) -> None:
    """Slow signing services and composite checks must get their own budgets."""

    def run(argv: tuple[str, ...], **kwargs: object) -> SimpleNamespace:
        """Simulate native completion after the observed short deadline.

        Returns:
            A healthy native response when its deadline is sufficient.

        Raises:
            subprocess.TimeoutExpired: The command was given too little time.

        """
        timeout = kwargs["timeout"]
        assert isinstance(timeout, int)
        if duration > timeout:
            raise subprocess.TimeoutExpired(argv, timeout)
        return SimpleNamespace(returncode=0, stdout="verified", stderr="")

    monkeypatch.setattr(manager.subprocess, "run", run)
    assert manager.command(*args) == "verified"


def test_native_inspection_still_has_finite_deadline(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """An unresponsive signing service must still block rather than pass."""

    def run(argv: tuple[str, ...], **kwargs: object) -> None:
        """Model a signing command which never completes.

        Raises:
            subprocess.TimeoutExpired: The finite deadline expires.

        """
        timeout = kwargs["timeout"]
        assert isinstance(timeout, int)
        assert 0 < timeout <= MAX_SIGNATURE_SECONDS
        raise subprocess.TimeoutExpired(argv, timeout)

    monkeypatch.setattr(manager.subprocess, "run", run)
    with pytest.raises(subprocess.TimeoutExpired):
        manager.command("/usr/bin/codesign", "--verify", "fixture.app")
