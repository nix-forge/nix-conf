"""Exercise Jujutsu identity rollback with synthetic values."""

from __future__ import annotations

import runpy
import stat
import tempfile
import unittest
from pathlib import Path

import tomllib

ROOT = Path(__file__).resolve().parents[2]
IDENTITY = runpy.run_path(
    str(ROOT / "modules/home/dev/scripts/write-jujutsu-identity.py")
)


class SecretTemplateTests(unittest.TestCase):
    """Verify identity fallback without modifying template generations."""

    def test_rollback_replaces_link_without_writing_generation(self) -> None:
        """Both live and dangling old template links become private regular files."""
        for dangling in (False, True):
            with (
                self.subTest(dangling=dangling),
                tempfile.TemporaryDirectory() as temporary,
            ):
                root = Path(temporary)
                generation = root / "old-generation.toml"
                if not dangling:
                    generation.write_text("old generation\n", encoding="utf-8")
                    generation.chmod(0o400)
                destination = root / "conf.d/90-local-identity.toml"
                destination.parent.mkdir()
                destination.symlink_to(generation)
                name = 'Alice "Quoted" \\ Example 🚀 \x7f'
                IDENTITY["_write_identity"](
                    destination, name, "fixture@example.invalid"
                )
                self.assertFalse(destination.is_symlink())
                self.assertEqual(
                    tomllib.loads(destination.read_text())["user"]["name"], name
                )
                self.assertEqual(stat.S_IMODE(destination.stat().st_mode), 0o600)
                self.assertEqual(stat.S_IMODE(destination.parent.stat().st_mode), 0o700)
                if dangling:
                    self.assertFalse(generation.exists())
                else:
                    self.assertEqual(generation.read_text(), "old generation\n")
                self.assertEqual(list(destination.parent.glob(".identity-*")), [])

    def test_missing_identity_removes_link_without_touching_target(self) -> None:
        """A missing fallback identity never truncates an old generation."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            generation = root / "generation.toml"
            generation.write_text("unchanged", encoding="utf-8")
            destination = root / "identity.toml"
            destination.symlink_to(generation)
            IDENTITY["_write_identity"](destination, "", "")
            self.assertFalse(destination.is_symlink())
            self.assertEqual(generation.read_text(), "unchanged")
