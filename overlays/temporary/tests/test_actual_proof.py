"""Reject unrelated build failures and broken installed Actual resources."""

from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from types import ModuleType
from unittest.mock import patch


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


_CSS = _module("actual-css-result")
_RUNTIME = _module("actual-runtime")
_SIDEBAR = "[vite:load-fallback] Could not load /source/packages/component-library/src/themes/sidebar-redesign-light.css?inline (imported by /source/packages/desktop-client/src/style/theme.tsx): ENOENT: no such file or directory"


class ActualProofTest(unittest.TestCase):
    """Require specific CSS regressions and truthful packaged runtime witnesses."""

    @staticmethod
    def test_raw_css_failure() -> None:
        """Test raw css failure."""
        _CSS.verify(_SIDEBAR.replace("sidebar-redesign-light", "dark"), 1, "raw")

    @staticmethod
    def test_new_fifth_css_failure() -> None:
        """Test new fifth css failure."""
        _CSS.verify("\x1b[31m" + _SIDEBAR + "\x1b[0m", 1, "four")

    def test_success_cannot_be_failure_evidence(self) -> None:
        """Test success cannot be failure evidence."""
        with self.assertRaisesRegex(ValueError, "failed build"):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library proof fixtures do not require pytest.
            _CSS.verify(_SIDEBAR, 0, "four")

    def test_crash_cannot_be_failure_evidence(self) -> None:
        """Test crash cannot be failure evidence."""
        with self.assertRaisesRegex(ValueError, "signal"):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library proof fixtures do not require pytest.
            _CSS.verify(_SIDEBAR, 139, "raw")

    def test_native_node_failure_is_rejected(self) -> None:
        """Test native node failure is rejected."""
        with self.assertRaisesRegex(ValueError, "Node or native-addon"):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library proof fixtures do not require pytest.
            _CSS.verify(
                _SIDEBAR + "\nError [ERR_DLOPEN_FAILED]: incompatible ABI", 1, "four"
            )

    def test_four_path_fix_must_fail_at_new_import(self) -> None:
        """Test four path fix must fail at new import."""
        with self.assertRaisesRegex(ValueError, "exact Actual theme"):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library proof fixtures do not require pytest.
            _CSS.verify(_SIDEBAR.replace("sidebar-redesign-light", "dark"), 1, "four")

    def test_other_importer_is_not_evidence(self) -> None:
        """Test other importer is not evidence."""
        with self.assertRaisesRegex(ValueError, "exact Actual theme"):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library proof fixtures do not require pytest.
            _CSS.verify(
                _SIDEBAR.replace("desktop-client/src/style/theme.tsx", "unrelated.tsx"),
                1,
                "raw",
            )

    def test_css_mentions_without_resolver_error_rejected(self) -> None:
        """Test css mentions without resolver error rejected."""
        with self.assertRaisesRegex(ValueError, "exact Actual theme"):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library proof fixtures do not require pytest.
            _CSS.verify(
                "themes/sidebar-redesign-light.css and desktop-client/src/style/theme.tsx",
                1,
                "four",
            )

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


if __name__ == "__main__":
    unittest.main()
