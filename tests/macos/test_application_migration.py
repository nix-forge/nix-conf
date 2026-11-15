"""Exercise canonical-path migrations without touching host applications."""

from __future__ import annotations

import importlib.util
import json
import shutil
import sys
from pathlib import Path

import pytest

SPEC = importlib.util.spec_from_file_location(
    "application_migration_fixture",
    Path(__file__).parents[2] / "modules/home/macos/application_lifecycle.py",
)
assert SPEC
assert SPEC.loader
manager = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = manager
SPEC.loader.exec_module(manager)

OLD = {"build": "10", "uuids": ["OLD"], "cdhashes": ["old"]}
NEW = {"build": "11", "uuids": ["NEW"], "cdhashes": ["new"]}


def write_bundle(path: Path, identity: dict) -> None:
    """Create a complete disposable bundle with independently readable bytes."""
    path.mkdir(parents=True)
    (path / "identity.json").write_text(json.dumps(identity))
    (path / "payload").write_text("complete vendor payload")


class FilesystemNative:
    """Model vendor verification while observing real copy/retirement effects."""

    def __init__(self) -> None:
        """Start without running processes or injected failures."""
        self.live = []
        self.calls = []
        self.foreign = set()
        self.fail_after_move = False
        self.fail_unregister = False

    def inspect(self, path: Path, _app: dict) -> dict:
        """Return sealed fixture bytes or reject the vendor verification boundary.

        Returns:
            The independent bundle identity.

        """
        if path in self.foreign:
            manager.fail("Vendor signature mismatch")
        return json.loads((path / "identity.json").read_text())

    def running(self, _app: dict) -> list:
        """Return the controlled GUI inventory.

        Returns:
            A fresh process list.

        """
        return self.live.copy()

    def process(self, _pid: int) -> tuple:
        """Return the currently mapped fixture identity.

        Returns:
            Kernel UUID, incarnation, version and CDHash.

        """
        value = self.inspect(Path(self.live[0]["path"]), {})
        return value["uuids"][0], 123, 1, value["cdhashes"][0]

    def copy(self, source: Path, target: Path) -> None:
        """Copy a whole fixture without changing its identity."""
        self.calls.append(("copy", str(target)))
        shutil.copytree(source, target)

    def swap(self, staged: Path, installed: Path) -> None:
        """Model exchange while retaining the previous complete directory."""
        self.calls.append(("swap", str(installed)))
        if installed.exists():
            temporary = staged.parent / "exchange"
            installed.rename(temporary)
            staged.rename(installed)
            temporary.rename(staged)
        else:
            staged.rename(installed)

    def move(self, source: Path, destination: Path) -> None:
        """Retire a complete previous copy, optionally failing after mutation.

        Raises:
            OSError: Injected interruption after the full directory was moved.

        """
        self.calls.append(("move", str(source)))
        assert not destination.exists()
        source.rename(destination)
        if self.fail_after_move:
            message = "injected interruption"
            raise OSError(message)

    def register(self, path: Path) -> None:
        """Record the chosen canonical URL."""
        self.calls.append(("register", str(path)))

    def unregister(self, path: Path, _app: dict) -> None:
        """Retire only the selected legacy URL, optionally failing closed."""
        self.calls.append(("unregister", str(path)))
        if self.fail_unregister:
            manager.fail("injected registry failure")


def fixture(
    tmp_path: Path, *, bundle: str = "Managed.app", previous: str = "Original.app"
) -> tuple:
    """Select a renamed target while retaining an older signed canonical copy.

    Returns:
        Native boundary, application policy and copied application directory.

    """
    source = tmp_path / "selected" / "Original.app"
    write_bundle(source, NEW)
    directory = tmp_path / "Apps"
    directory.mkdir()
    write_bundle(directory / previous, OLD)
    app = {
        "bundle": bundle,
        "bundleId": "org.example.app",
        "teamId": "VENDOR",
        "source": str(source),
        "previousBundles": [previous],
    }
    return FilesystemNative(), app, directory


@pytest.mark.parametrize(
    ("bundle", "previous"),
    [("Managed.app", "Original.app"), ("Original.app", "Managed.app")],
)
@pytest.mark.parametrize("same_version", [False, True])
def test_signed_migration_preserves_old_copy_and_retires_both_urls(
    tmp_path: Path,
    bundle: str,
    previous: str,
    same_version: bool,
) -> None:
    """The chosen new path and complete backup retain their independent identities."""
    native, app, directory = fixture(tmp_path, bundle=bundle, previous=previous)
    retained = NEW if same_version else OLD
    (directory / previous / "identity.json").write_text(json.dumps(retained))
    assert "retained" in manager.install(native, app, directory)
    (backup_dir,) = tmp_path.glob(".hm-app-update-*.noindex")
    backup = backup_dir / previous
    assert native.inspect(directory / bundle, app) == NEW
    assert native.inspect(backup, app) == retained
    assert not (directory / previous).exists()
    assert (backup / "payload").read_text() == "complete vendor payload"
    assert [path for operation, path in native.calls if operation == "unregister"] == [
        str(directory / previous),
        str(backup),
    ]
    journal = json.loads((backup_dir / "transaction.json").read_text())
    assert journal["status"] == "registered-user"
    assert journal["previous"][str(directory / previous)] == retained
    native.calls.clear()
    assert manager.install(native, app, directory) == "unchanged"
    assert native.calls == []


@pytest.mark.parametrize(
    ("bundle", "previous"),
    [("Managed.app", "Original.app"), ("Original.app", "Managed.app")],
)
def test_running_previous_path_blocks_every_mutation(
    tmp_path: Path, bundle: str, previous: str
) -> None:
    """An app must fully quit even if its signed version is unchanged."""
    native, app, directory = fixture(tmp_path, bundle=bundle, previous=previous)
    native.live = [{"pid": 42, "path": str(directory / previous)}]
    with pytest.raises(manager.LifecycleError, match="Quit"):
        manager.install(native, app, directory)
    assert native.calls == []
    assert (directory / previous).is_dir()
    assert not (directory / bundle).exists()


@pytest.mark.parametrize("failure", ["signature", "downgrade", "symlink"])
@pytest.mark.parametrize(
    ("bundle", "previous_name"),
    [("Managed.app", "Original.app"), ("Original.app", "Managed.app")],
)
def test_unverified_legacy_copy_is_never_retired(
    tmp_path: Path, failure: str, bundle: str, previous_name: str
) -> None:
    """A chosen filename cannot authorize retiring a foreign or redirected app."""
    native, app, directory = fixture(tmp_path, bundle=bundle, previous=previous_name)
    previous = directory / previous_name
    if failure == "signature":
        native.foreign.add(previous)
    elif failure == "downgrade":
        (previous / "identity.json").write_text(json.dumps(NEW | {"build": "12"}))
    else:
        previous.rename(tmp_path / "foreign.app")
        previous.symlink_to(tmp_path / "foreign.app", target_is_directory=True)
    with pytest.raises(manager.LifecycleError):
        manager.install(native, app, directory)
    assert native.calls == []
    assert previous.exists()


@pytest.mark.parametrize("failure", ["move", "registry"])
@pytest.mark.parametrize(
    ("bundle", "previous"),
    [("Managed.app", "Original.app"), ("Original.app", "Managed.app")],
)
def test_interrupted_retirement_keeps_complete_bundles_and_intent(
    tmp_path: Path, failure: str, bundle: str, previous: str
) -> None:
    """Never clean a transaction after a canonical mutation might have happened."""
    native, app, directory = fixture(tmp_path, bundle=bundle, previous=previous)
    native.fail_after_move = failure == "move"
    native.fail_unregister = failure == "registry"
    with pytest.raises(manager.LifecycleError, match="journal retained"):
        manager.install(native, app, directory)
    (backup_dir,) = tmp_path.glob(".hm-app-update-*.noindex")
    assert native.inspect(directory / bundle, app) == NEW
    assert native.inspect(backup_dir / previous, app) == OLD
    assert (
        json.loads((backup_dir / "transaction.json").read_text())["status"]
        == "retire-intent"
    )
    assert not any(operation == "register" for operation, _ in native.calls)


def test_retry_can_finish_when_destination_already_matches(tmp_path: Path) -> None:
    """A previously installed target does not bypass guarded legacy retirement."""
    native, app, directory = fixture(tmp_path)
    write_bundle(directory / "Managed.app", NEW)
    manager.install(native, app, directory)
    assert not any(operation in {"copy", "swap"} for operation, _ in native.calls)
    assert not (directory / "Original.app").exists()
    assert native.calls[-1] == ("register", str(directory / "Managed.app"))


@pytest.mark.parametrize(
    "previous", [["../Other.app"], ["Managed.app"], ["Original.app", "original.app"]]
)
def test_legacy_names_are_confined_and_case_distinct(
    tmp_path: Path, previous: list
) -> None:
    """Manifest mistakes cannot retire another app or alias the target on APFS."""
    native, app, directory = fixture(tmp_path)
    app["previousBundles"] = previous
    with pytest.raises(manager.LifecycleError):
        manager.install(native, app, directory)
    assert native.calls == []


@pytest.mark.skipif(
    sys.platform != "darwin", reason="Native exclusive directory rename"
)
def test_native_retirement_cannot_replace_even_an_empty_destination(
    tmp_path: Path,
) -> None:
    """The real Darwin primitive closes the existence-check/rename overwrite race."""
    source, destination = tmp_path / "source", tmp_path / "destination"
    source.mkdir()
    destination.mkdir()
    with pytest.raises(manager.LifecycleError, match="Exclusive"):
        manager.Native.move(source, destination)
    assert source.is_dir()
    assert destination.is_dir()


def registration_fixture(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> tuple:
    """Model independent root/user views after a backup followed its moved inode.

    Returns:
        The native boundary, policy, manifest, both views and retained backup.

    """
    native, app, directory = fixture(tmp_path)
    manager.install(native, app, directory)
    (archive,) = tmp_path.glob(".hm-app-update-*.noindex")
    backup = archive / "Original.app"
    canonical = directory / app["bundle"]
    views = {"root": {canonical, backup}, "user": {canonical, backup}}
    native.calls.clear()
    register, unregister = native.register, native.unregister

    def root_register(path: Path) -> None:
        """Update only root's selected URL."""
        register(path)
        views["root"].add(path)

    def root_unregister(path: Path, policy: dict) -> None:
        """Retire root's selected URL without touching its complete bundle."""
        unregister(path, policy)
        views["root"].discard(path)

    def command(*args: str) -> str:
        """Return native URL evidence or perform a scoped user metadata update.

        Returns:
            Structured native evidence or an empty tool response.

        """
        context = "user" if args[0] == "user-context" else "root"
        if "--registered-paths" in args:
            return json.dumps({app["bundleId"]: sorted(map(str, views[context]))})
        assert context == "user"
        if args[-2] == "-u":
            views["user"].discard(Path(args[-1]))
        else:
            assert args[-2] == "-f"
            views["user"].add(Path(args[-1]))
        return ""

    monkeypatch.setattr(native, "register", root_register)
    monkeypatch.setattr(native, "unregister", root_unregister)
    monkeypatch.setattr(manager, "command", command)
    manifest = {
        "registryHelper": "registry-query",
        "queryScript": "query.js",
        "appsDirectory": str(directory),
    }
    return native, app, manifest, views, backup


def test_root_and_user_backup_registrations_are_retired_before_success(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A moved inode cannot remain an ordinary launch target in either context."""
    native, app, manifest, views, backup = registration_fixture(tmp_path, monkeypatch)
    manager.reconcile_system_registration(native, manifest, app, ["user-context"])
    canonical = Path(manifest["appsDirectory"]) / app["bundle"]
    assert views == {"root": {canonical}, "user": {canonical}}
    assert native.inspect(backup, app) == OLD
    assert (backup / "payload").is_file()


@pytest.mark.parametrize(
    "failure", ["foreign-backup", "manual-copy", "redirected-parent"]
)
def test_root_cleanup_validates_every_url_before_mutating_any(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, failure: str
) -> None:
    """Native metadata cannot authorize arbitrary root registration cleanup."""
    native, app, manifest, views, backup = registration_fixture(tmp_path, monkeypatch)
    if failure == "foreign-backup":
        native.foreign.add(backup)
    elif failure == "manual-copy":
        views["root"].add(tmp_path / "Manual.app")
    else:
        redirected = tmp_path / ".hm-app-update-redirected.noindex"
        redirected.symlink_to(backup.parent, target_is_directory=True)
        views["root"].add(redirected / backup.name)
    with pytest.raises(manager.LifecycleError):
        manager.reconcile_system_registration(native, manifest, app, ["user-context"])
    assert native.calls == []
    assert backup in views["root"]
    assert backup in views["user"]


def test_root_registration_success_requires_both_independent_views(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Successful tool exit codes cannot hide a surviving user backup bookmark."""
    native, app, manifest, _views, backup = registration_fixture(tmp_path, monkeypatch)
    original = manager.registered_paths

    def stale_user(manifest: dict, app: dict, prefix: list) -> set:
        """Keep reporting the stale user URL despite successful metadata calls.

        Returns:
            The independent stale native inventory.

        """
        paths = original(manifest, app, prefix)
        return paths | {backup} if prefix else paths

    monkeypatch.setattr(manager, "registered_paths", stale_user)
    with pytest.raises(
        manager.LifecycleError, match="remains eligible after retirement"
    ):
        manager.reconcile_system_registration(native, manifest, app, ["user-context"])


@pytest.mark.parametrize(
    "path",
    [
        "relative.app",
        "/nix/store/../Applications/Other.app",
        "/Applications//Other.app",
    ],
)
def test_native_registration_paths_must_be_normalized_absolute_urls(
    monkeypatch: pytest.MonkeyPatch, path: str
) -> None:
    """An unsupported native response fails before its URL can select an action."""
    monkeypatch.setattr(
        manager, "command", lambda *_: json.dumps({"org.example.app": [path]})
    )
    with pytest.raises(manager.LifecycleError, match="Noncanonical"):
        manager.registered_paths(
            {"registryHelper": "query", "queryScript": "query.js"},
            {"bundleId": "org.example.app"},
            [],
        )


def test_absent_backup_requires_no_unregister_scan(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """An unregistered hidden backup must not trigger Launch Services scan errors."""
    calls = []
    monkeypatch.setattr(manager, "registered_paths", lambda *_: set())
    monkeypatch.setattr(manager, "command", lambda *args: calls.append(args))
    native = manager.Native("query.js", "rsync", "registry-query")
    native.unregister(Path("/Apps/.hm-app-update-example.noindex/Original.app"), {})
    assert calls == []


@pytest.mark.parametrize("failure", ["command", "still-eligible"])
def test_native_retirement_errors_remain_blocking(
    monkeypatch: pytest.MonkeyPatch, failure: str
) -> None:
    """An eligible URL must retire successfully; neither error can be ignored."""
    path = Path("/Apps/Original.app")
    monkeypatch.setattr(manager, "registered_paths", lambda *_: {path})

    def command(*_args: str) -> str:
        """Reject the native mutation or leave the independent URL unchanged.

        Returns:
            An empty tool response for the stale-inventory case.

        """
        if failure == "command":
            manager.fail("native unregister failed")
        return ""

    monkeypatch.setattr(manager, "command", command)
    with pytest.raises(manager.LifecycleError):
        manager.unregister_registration({}, {}, path, ["user-context"])
