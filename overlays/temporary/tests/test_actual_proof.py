"""Validate real source layout evidence and installed Actual runtime resources."""

from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from typing import TYPE_CHECKING
from unittest.mock import patch

if TYPE_CHECKING:
    from types import ModuleType


def _module(name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(
        name, Path(__file__).with_name(name + ".py")
    )
    if spec is None or spec.loader is None:
        message = "Cannot load the local proof helper"
        raise ImportError(message)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


_SOURCE = _module("actual-css-result")
_RUNTIME = _module("actual-runtime")


def _tree(root: Path) -> Path:
    names = ("dark.css", "sidebar-redesign-light.css")
    component = root / "packages/component-library"
    directory = component / "src/themes"
    directory.mkdir(parents=True)
    (component / "package.json").write_text(
        json.dumps({
            "exports": {f"./themes/{name}": f"./src/themes/{name}" for name in names}
        })
    )
    theme = root / "packages/desktop-client/src/style/theme.tsx"
    theme.parent.mkdir(parents=True)
    theme.write_text(
        "\n".join(
            f"import css{index} from '@actual-app/components/themes/{name}?inline';"
            for index, name in enumerate(names)
        )
        + "\n"
    )
    for name in names:
        (directory / name).write_text(f"/* source stylesheet fixture: {name} */")
    return theme


class ActualProofTest(unittest.TestCase):
    """Verify case-collision removal and actual packaged runtime resource checks."""

    def test_runtime_serves_installed_assets(self) -> None:
        """Test runtime serves installed assets."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            markup = '<html><script src="/app.js"></script><link rel="stylesheet" href="/app.css"></html>'
            (root / "index.html").write_text(markup)
            (root / "app.js").write_bytes(b"installed-script")
            (root / "app.css").write_bytes(b"installed-css")
            replies = {
                "health": json.dumps({"status": "UP"}).encode(),
                "info": json.dumps({
                    "build": {"version": "fixture", "name": "@actual-app/sync-server"}
                }).encode(),
                "account/needs-bootstrap": json.dumps({
                    "status": "ok",
                    "data": {"bootstrapped": False},
                }).encode(),
                "": markup.encode(),
                "/app.js": b"installed-script",
                "/app.css": b"installed-css",
            }
            with patch.object(
                _RUNTIME, "get", side_effect=lambda _port, path: replies[path]
            ):
                _RUNTIME.verify(12345, root, "fixture")
                replies["/app.js"] = b"wrong-script"
                with self.assertRaisesRegex(ValueError, "differs from the installed"):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library proof fixtures do not require pytest.
                    _RUNTIME.verify(12345, root, "fixture")

    def test_missing_asset_rejected(self) -> None:
        """Test missing asset rejected."""
        with (
            tempfile.TemporaryDirectory() as temporary,
            self.assertRaisesRegex(ValueError, "absent"),  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library proof fixtures do not require pytest.
        ):
            _RUNTIME.asset_paths('<script src="/missing.js"></script>', Path(temporary))

    def test_external_asset_rejected(self) -> None:
        """Test external asset rejected."""
        with (
            tempfile.TemporaryDirectory() as temporary,
            self.assertRaisesRegex(ValueError, "local assets"),  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library proof fixtures do not require pytest.
        ):
            _RUNTIME.asset_paths(
                '<script src="https://example.invalid/app.js"></script>',
                Path(temporary),
            )

    def test_asset_escape_rejected(self) -> None:
        """Test asset escape rejected."""
        with (
            tempfile.TemporaryDirectory() as temporary,
            self.assertRaisesRegex(ValueError, "outside webRoot"),  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library proof fixtures do not require pytest.
        ):
            _RUNTIME.asset_paths(
                '<script src="/%2e%2e/escape.js"></script>', Path(temporary)
            )

    def test_empty_page_rejected(self) -> None:
        """Test empty page rejected."""
        with (
            tempfile.TemporaryDirectory() as temporary,
            self.assertRaisesRegex(ValueError, "no executable"),  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library proof fixtures do not require pytest.
        ):
            _RUNTIME.asset_paths("<html></html>", Path(temporary))

    def test_source_inventory_does_not_mutate(self) -> None:
        """Read exact entries/imports/exports without changing source bytes."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            _tree(root)
            before = {
                file.relative_to(root).as_posix(): file.read_bytes()
                for file in root.rglob("*")
                if file.is_file()
            }
            result = _SOURCE.inventory(root)
            after = {
                file.relative_to(root).as_posix(): file.read_bytes()
                for file in root.rglob("*")
                if file.is_file()
            }
            self.assertEqual(before, after)  # ruff: ignore[pytest-unittest-assertion] - Standard library source/runtime regressions.
            self.assertEqual(result["caseFoldedThemeEntries"], ["themes"])  # ruff: ignore[pytest-unittest-assertion] - Standard library source/runtime regressions.
            self.assertIn("sidebar-redesign-light.css", result["imports"])  # ruff: ignore[pytest-unittest-assertion] - Standard library source/runtime regressions.

    def test_old_case_collision_rejected(self) -> None:
        """Exact entry names detect the old case conflict on every test platform."""
        with self.assertRaisesRegex(ValueError, "case-colliding"):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library source/runtime regressions.
            _SOURCE.check_directory_names(["Themes", "themes"])

    def test_uppercase_lookup_not_lowercase_entry(self) -> None:
        """A case-insensitive path lookup cannot substitute for an exact entry."""
        with self.assertRaisesRegex(ValueError, "case-colliding"):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library source/runtime regressions.
            _SOURCE.check_directory_names(["Themes"])

    def test_case_hacked_source_rejected(self) -> None:
        """Do not accept old or induced case-hacked source as the new raw tree."""
        with self.assertRaisesRegex(ValueError, "case-colliding"):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library source/runtime regressions.
            _SOURCE.check_directory_names(["themes", "themes~nix~case~hack~1"])

    def test_missing_sidebar_source_rejected(self) -> None:
        """Keep the new source stylesheet requirement meaningful."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            _tree(root)
            (
                root
                / "packages/component-library/src/themes/sidebar-redesign-light.css"
            ).unlink()
            with self.assertRaisesRegex(ValueError, "stylesheet is missing"):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library source/runtime regressions.
                _SOURCE.inventory(root)

    def test_mismatched_export_rejected(self) -> None:
        """CSS exports must point to the intact normal source files."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            _tree(root)
            manifest = root / "packages/component-library/package.json"
            data = json.loads(manifest.read_text())
            data["exports"]["./themes/sidebar-redesign-light.css"] = "./unrelated.css"
            manifest.write_text(json.dumps(data))
            with self.assertRaisesRegex(ValueError, "export does not match"):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library source/runtime regressions.
                _SOURCE.inventory(root)


if __name__ == "__main__":
    unittest.main()
