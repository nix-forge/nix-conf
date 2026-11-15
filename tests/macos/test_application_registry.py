"""Exercise scoped registration repair, recovery, and canonical CLI dispatch."""

from __future__ import annotations

import importlib.util
import json
import plistlib
import re
import shlex
import shutil
import subprocess  # ruff: ignore[suspicious-subprocess-import]
import sys
from pathlib import Path
from typing import TYPE_CHECKING
from unittest import mock

import pytest

if TYPE_CHECKING:
    from collections.abc import Sequence

MODULE_DIRECTORY = Path(__file__).parents[2] / "modules/home/macos"
SPEC = importlib.util.spec_from_file_location(
    "application_registry", MODULE_DIRECTORY / "application_registry.py"
)
assert SPEC is not None
assert SPEC.loader is not None
manager = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = manager
SPEC.loader.exec_module(manager)


class FixtureRegistry:
    """Model the native URL registry without touching any host applications."""

    def __init__(self, identifier: str, paths: list[str]) -> None:
        """Copy fixture state and retain the operation history."""
        self.identifier = identifier
        self.available = list(paths)
        self.operations: list[tuple[str, str]] = []

    def paths(self, identifiers: Sequence[str]) -> dict[str, list[str]]:
        """Return a snapshot.

        Returns:
            A copy of the simulated native registry.

        """
        assert list(identifiers) == [self.identifier]
        return {self.identifier: list(self.available)}

    def register(self, path: Path) -> None:
        """Expose the chosen copied app."""
        self.operations.append(("register", str(path)))
        if str(path) not in self.available:
            self.available.append(str(path))

    def unregister(self, path: Path) -> None:
        """Drop one registration, leaving its files intact."""
        self.operations.append(("unregister", str(path)))
        self.available.remove(str(path))


def make_app(path: Path, identifier: str = "org.example.editor") -> Path:
    """Create a minimal binary-plist application fixture.

    Returns:
        The application directory.

    """
    contents = path / "Contents"
    contents.mkdir(parents=True)
    (contents / "Info.plist").write_bytes(
        plistlib.dumps({"CFBundleIdentifier": identifier}, fmt=plistlib.FMT_BINARY)
    )
    return path


def test_repair_removes_only_store_registrations_and_is_repeatable(
    tmp_path: Path,
) -> None:
    """A copied bundle replaces store candidates without unregistering user apps."""
    app = make_app(tmp_path / "Applications/Home Manager Apps/Editor.app")
    manual = "/Applications/Editor Preview.app"
    old = "/nix/store/old-editor/Applications/Editor.app"
    registry = FixtureRegistry("org.example.editor", [old, manual])
    args = (app.parent, app.parent.parent, tmp_path / "state", registry)
    manager.reconcile(*args)
    assert registry.available == [manual, str(app)]
    assert registry.operations == [("unregister", old), ("register", str(app))]
    manager.reconcile(*args)
    assert registry.available == [manual, str(app)]


def test_check_catches_competing_store_launches_before_repair(tmp_path: Path) -> None:
    """The check rejects the actual duplicate-registration failure pattern."""
    app = make_app(tmp_path / "apps/Editor.app")
    registry = FixtureRegistry(
        "org.example.editor", [str(app), "/nix/store/old/Applications/Editor.app"]
    )
    with pytest.raises(ValueError, match="did not converge"):
        manager.reconcile(
            app.parent, tmp_path / "legacy", tmp_path / "state", registry, mode="check"
        )
    assert registry.operations == []


def test_failed_native_removal_is_reported(tmp_path: Path) -> None:
    """A successful registration call alone cannot hide remaining duplicates."""
    app = make_app(tmp_path / "apps/Editor.app")
    old = "/nix/store/old/Applications/Editor.app"
    registry = FixtureRegistry("org.example.editor", [str(app), old])
    with (
        mock.patch.object(registry, "unregister"),
        pytest.raises(ValueError, match="did not converge"),
    ):
        manager.reconcile(app.parent, tmp_path / "legacy", tmp_path / "state", registry)


def test_preview_creates_no_recovery_state(tmp_path: Path) -> None:
    """Preview never changes native registration or creates recovery files."""
    app = make_app(tmp_path / "apps/Editor.app")
    registry = FixtureRegistry("org.example.editor", [])
    state = tmp_path / "state"
    manager.reconcile(app.parent, tmp_path / "legacy", state, registry, mode="dry-run")
    assert registry.operations == []
    assert not state.exists()


def test_legacy_link_is_archived_with_recovery_journal(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Migration preserves the old symlink and never edits the store bundle."""
    # An isolated store root permits real filesystem operations in the fixture.
    store = tmp_path / "store"
    monkeypatch.setattr(
        manager,
        "STORE_APP",
        re.compile(re.escape(str(store)) + r"/[^/]+/Applications/[^/]+\.app"),
    )
    app = make_app(tmp_path / "Applications/Home Manager Apps/Editor.app")
    old = make_app(store / "old-editor/Applications/Editor.app")
    link = app.parent.parent / "Editor.app"
    link.symlink_to(old)
    state = tmp_path / "recovery.noindex"
    state.mkdir()
    registry = FixtureRegistry("org.example.editor", [str(old)])
    manager.reconcile(app.parent, link.parent, state, registry)
    assert not link.is_symlink()
    journals = list(state.glob("migration-*/*.json"))
    assert len(journals) == 1
    journal = json.loads(journals[0].read_text())
    assert journal["original"] == str(link)
    saved = Path(journal["saved"])
    assert saved.is_symlink()
    assert saved.readlink() == old
    assert manager.bundle_identifier(old) == "org.example.editor"
    saved.rename(link)
    assert link.resolve() == old


def test_manual_apps_and_different_id_links_are_preserved(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Name matching alone never authorizes moving a different application."""
    store = tmp_path / "store"
    monkeypatch.setattr(
        manager,
        "STORE_APP",
        re.compile(re.escape(str(store)) + r"/[^/]+/Applications/[^/]+\.app"),
    )
    app = make_app(tmp_path / "Applications/Home Manager Apps/Editor.app")
    other = make_app(store / "other/Applications/Editor.app", "org.example.other")
    link = app.parent.parent / "Editor.app"
    link.symlink_to(other)
    assert manager.legacy_links(manager.applications(app.parent), link.parent) == []
    link.unlink()
    make_app(link)
    assert manager.legacy_links(manager.applications(app.parent), link.parent) == []


@pytest.mark.parametrize("invalid", ["symlink", "duplicate-id", "missing-plist"])
def test_invalid_inventory_fails_before_any_mutation(
    tmp_path: Path, invalid: str
) -> None:
    """Incomplete copying or duplicate identities cannot trigger partial cleanup."""
    app = make_app(tmp_path / "apps/Editor.app")
    if invalid == "symlink":
        (app.parent / "Link.app").symlink_to(app)
    elif invalid == "duplicate-id":
        make_app(app.parent / "Other.app")
    else:
        (app.parent / "Missing.app").mkdir()
    registry = FixtureRegistry("org.example.editor", [])
    with pytest.raises((ValueError, FileNotFoundError)):
        manager.reconcile(app.parent, tmp_path / "legacy", tmp_path / "state", registry)
    assert registry.operations == []


@pytest.mark.parametrize(
    "path",
    [
        "/Applications/Editor.app",
        "/nix/store/pkg/Applications/Editor.app/Contents/Helper.app",
        "/nix/store/pkg/bin/Editor.app",
    ],
)
def test_only_top_level_store_apps_are_candidates(path: str) -> None:
    """Helpers and unrelated installations stay outside the cleanup boundary."""
    assert manager.STORE_APP.fullmatch(path) is None


def test_disabled_store_tombstones_are_not_launchable_duplicates() -> None:
    """AppKit can return unregistered URLs; only explicit native tombstones qualify."""
    old = "/nix/store/old/Applications/Editor.app"
    enabled = "/nix/store/new/Applications/Editor.app"
    manual = "/Applications/Manual.app"
    recovery = "/Applications/.hm-app-update-fixture.noindex/Editor.app"
    dump = "\n".join([
        "-" * 80,
        f"path:                       {old} (0x328f4)",
        "bundle flags:               launch-disabled (0000000000000080)",
        "-" * 80,
        f"path:                       {enabled} (0x1234)",
        "bundle flags:               has-display-name (0000000000000002)",
        "-" * 80,
        f"path:                       {manual} (0x4567)",
        "bundle flags:               launch-disabled (0000000000000080)",
    ])
    dump += "\n" + "\n".join([
        "-" * 80,
        f"path:                       {recovery} (0x4568)",
        "bundle flags:               launch-disabled (0000000000000080)",
    ])
    assert manager.disabled_registrations(dump) == {old, recovery}
    assert manager.disabled_registrations("unrecognized output") == set()


def test_registered_paths_query_is_read_only(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture
) -> None:
    """A root/user inventory query never creates reconciliation state."""
    registry = FixtureRegistry("org.example.app", [str(tmp_path / "Editor.app")])
    monkeypatch.setattr(manager, "NativeRegistry", lambda _: registry)
    monkeypatch.setattr(
        manager.sys,
        "argv",
        [
            "registry",
            "--query-script",
            "query.js",
            "--registered-paths",
            "org.example.app",
        ],
    )
    manager.main()
    assert json.loads(capsys.readouterr().out) == {
        "org.example.app": [str(tmp_path / "Editor.app")]
    }
    assert registry.operations == []
    assert list(tmp_path.iterdir()) == []


@pytest.mark.parametrize("native_cli", [True, False])
def test_launcher_preserves_arguments_and_status(
    tmp_path: Path, native_cli: bool
) -> None:
    """CLI dispatch retains --wait; GUI dispatch uses path-specific app reuse."""
    app = make_app(tmp_path / "Apps With Spaces/Editor.app")
    bash = shutil.which("bash")
    assert bash is not None
    target = app / "Contents/cli" if native_cli else tmp_path / "open"
    expected_exit_code = 23
    target.write_text(f"#!{bash}\nprintf '%s\\n' \"$@\"\nexit 23\n")
    target.chmod(0o755)
    replacements = {
        "app": str(app),
        "executable": "Contents/cli" if native_cli else "",
        "open": str(target),
    }
    source = (MODULE_DIRECTORY / "scripts/launch-managed-app.sh.in").read_text()
    for name, value in replacements.items():
        source = source.replace(f"@{name}@", shlex.quote(value))
    completed = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Rendered repository launcher and fixture executables.
        [bash, "-euc", source, "launcher", "--wait", "a file.txt", "$(literal)"],
        check=False,
        text=True,
        capture_output=True,
    )
    expected = ["--wait", "a file.txt", "$(literal)"]
    if not native_cli:
        expected = ["-a", str(app), "--args", *expected]
    assert completed.stdout.splitlines() == expected
    assert completed.returncode == expected_exit_code


def test_missing_copied_app_does_not_launch_store_fallback(tmp_path: Path) -> None:
    """An incomplete activation produces an actionable error, not another instance."""
    source = (MODULE_DIRECTORY / "scripts/launch-managed-app.sh.in").read_text()
    for name, value in {
        "app": str(tmp_path / "Missing.app"),
        "executable": "",
        "open": "/does/not/exist",
    }.items():
        source = source.replace(f"@{name}@", shlex.quote(value))
    bash = shutil.which("bash")
    assert bash is not None
    completed = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Rendered repository source with a missing fixture bundle.
        [bash, "-euc", source], check=False, capture_output=True, text=True
    )
    assert completed.returncode == 1
    assert "activate Home Manager first" in completed.stderr


def test_command_alias_preserves_the_primary_spelling(tmp_path: Path) -> None:
    """Case-sensitive stores retain lowercase access without changing the primary command."""
    binary = tmp_path / "bin/ChatGPT"
    binary.parent.mkdir()
    binary.write_text("canonical command\n")
    source = (MODULE_DIRECTORY / "scripts/link-command-alias.sh.in").read_text()
    source = source.replace("@name@", "ChatGPT").replace("@alias@", "chatgpt")
    bash = shutil.which("bash")
    assert bash is not None
    subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Repository alias helper and isolated output directory.
        [bash, "-euc", "out=$1\n" + source, "alias-test", str(tmp_path)], check=True
    )
    alias = tmp_path / "bin/chatgpt"
    assert alias.read_text() == "canonical command\n"
    if alias.name in [p.name for p in binary.parent.iterdir() if p.name != binary.name]:
        assert alias.is_symlink()
        assert alias.readlink() == Path("ChatGPT")
    assert binary.read_text() == "canonical command\n"
