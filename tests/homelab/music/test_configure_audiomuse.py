"""Persisted AudioMuse endpoint repair preserves credentials and other settings."""

import importlib.util
import unittest
from pathlib import Path
from typing import Any

SPEC = importlib.util.spec_from_file_location(
    "configure_audiomuse",
    Path(__file__).parents[3]
    / "hosts/nixos/desktop/local/homelab/music/scripts/configure_audiomuse.py",
)
assert SPEC is not None
assert SPEC.loader is not None
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


class ConfigureAudioMuseTest(unittest.TestCase):
    """Verify minimal updates and fail-closed connection checks."""

    def test_current_endpoint_causes_no_write(self) -> None:
        """Leave a correct endpoint untouched."""
        calls = []

        def request(_path: str, body: dict[str, Any] | None = None) -> dict[str, Any]:
            calls.append(body)
            return {
                "basic_fields": [
                    {"name": "NAVIDROME_URL", "value": "http://127.0.0.1:4533"}
                ]
            }

        self.assertFalse(module.reconcile(request, "http://127.0.0.1:4533"))
        self.assertEqual(calls, [None])

    def test_only_endpoint_is_changed_after_successful_probe(self) -> None:
        """Preserve credentials and all unrelated settings."""
        calls = []

        def request(_path: str, body: dict[str, Any] | None = None) -> dict[str, Any]:
            calls.append(body)
            if body is None:
                return {
                    "basic_fields": [
                        {"name": "NAVIDROME_URL", "value": "http://old.example.test"}
                    ]
                }
            return {"status": "ok"}

        self.assertTrue(module.reconcile(request, "http://127.0.0.1:4533"))
        self.assertEqual(
            calls[1:],
            [
                {
                    "config": {"NAVIDROME_URL": "http://127.0.0.1:4533"},
                    "test_connection": True,
                },
                {"config": {"NAVIDROME_URL": "http://127.0.0.1:4533"}},
            ],
        )

    def test_failed_probe_does_not_write(self) -> None:
        """Do not persist an endpoint that cannot connect."""
        calls = []

        def request(_path: str, body: dict[str, Any] | None = None) -> dict[str, Any]:
            calls.append(body)
            if body is None:
                return {
                    "basic_fields": [
                        {"name": "NAVIDROME_URL", "value": "http://old.example.test"}
                    ]
                }
            return {"status": "error"}

        with self.assertRaisesRegex(RuntimeError, "could not verify"):
            module.reconcile(request, "http://127.0.0.1:4533")
        self.assertEqual(len(calls), 2)

    def test_unknown_schema_fails_without_write(self) -> None:
        """Fail closed when the setup schema changes."""
        with self.assertRaisesRegex(RuntimeError, "does not expose"):
            module.reconcile(lambda _: {}, "http://127.0.0.1:4533")


if __name__ == "__main__":
    unittest.main()
