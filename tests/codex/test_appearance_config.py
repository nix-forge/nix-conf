"""Exercise the built appearance updater against real TOML syntax and file state."""

from __future__ import annotations

import os
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

import tomllib


class AppearanceConfigTests(unittest.TestCase):
    """Run with CODEX_APPEARANCE_SCRIPT pointing at the Nix-built wrapper."""

    def setUp(self) -> None:
        """Create a disposable configuration path."""
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name) / "config.toml"
        self.script = os.environ["CODEX_APPEARANCE_SCRIPT"]

    def update(self) -> subprocess.CompletedProcess[str]:
        """Run the generated wrapper and capture its exit status.

        Returns:
            The completed updater process.

        """
        return subprocess.run(
            [shutil.which("bash") or "/bin/bash", self.script, str(self.path)],
            capture_output=True,
            text=True,
            check=False,
        )

    def read(self) -> dict:
        """Parse the resulting TOML with an independent parser.

        Returns:
            Decoded TOML settings.

        """
        return tomllib.loads(self.path.read_text(encoding="utf-8"))

    def test_commented_and_quoted_headers(self) -> None:
        """Update equivalent table spellings without duplicate declarations."""
        for header in ("[desktop] # retained comment", "[ 'desktop' ]"):
            with self.subTest(header=header):
                self.path.write_text(f'{header}\ncustomPreference = "keep"\n')
                self.assertEqual(self.update().returncode, 0)
                desktop = self.read()["desktop"]
                self.assertEqual(desktop["customPreference"], "keep")
                self.assertEqual(desktop["appearanceTheme"], "dark")

    def test_inline_tables_and_dotted_keys(self) -> None:
        """Merge valid inline tables and dotted assignments."""
        for source in (
            'desktop = { appearanceTheme = "light", customPreference = true }\n',
            'desktop.appearanceTheme = "light"\ndesktop.customPreference = true\n',
        ):
            with self.subTest(source=source):
                self.path.write_text(source)
                self.assertEqual(self.update().returncode, 0)
                self.assertTrue(self.read()["desktop"]["customPreference"])
                self.assertEqual(self.read()["desktop"]["appearanceTheme"], "dark")

    def test_multiline_strings_are_not_tables(self) -> None:
        """Preserve table-shaped text inside multiline strings."""
        source = 'notes = """\n[desktop]\nappearanceTheme = "light"\n"""\n'
        self.path.write_text(source)
        original = self.read()["notes"]
        self.assertEqual(self.update().returncode, 0)
        self.assertEqual(self.read()["notes"], original)
        self.assertEqual(self.read()["desktop"]["appearanceTheme"], "dark")

    def test_preserves_unmanaged_settings_and_comments(self) -> None:
        """Retain unrelated application state and comments."""
        source = '# Keep this comment\nmodel = "example-model"\n\n[projects."/workspace/example"]\ntrust_level = "trusted"\n\n[desktop]\ncustomPreference = 42 # app-owned\n\n[desktop.appearanceLightChromeTheme]\ncontrast = 45\n'
        self.path.write_text(source)
        before = self.read()
        self.assertEqual(self.update().returncode, 0)
        after = self.read()
        for key in ("model", "projects"):
            self.assertEqual(after[key], before[key])
        self.assertEqual(after["desktop"]["customPreference"], 42)
        self.assertEqual(
            after["desktop"]["appearanceLightChromeTheme"], {"contrast": 45}
        )
        for comment in ("# Keep this comment", "# app-owned"):
            self.assertIn(comment, self.path.read_text(encoding="utf-8"))

    def test_clears_managed_font_faces_preserves_content_font(self) -> None:
        """Drop stale managed faces and retain user-owned content typography."""
        self.path.write_text(
            '[desktop.appearanceDarkChromeTheme.fonts]\nui = "Old UI"\ncode = "Old Code"\ncontent = "User Content"\nuiFace = { family = "Old UI", fullName = "Old", postscriptName = "Old" }\ncodeFace = { family = "Old Code", fullName = "Old", postscriptName = "Old" }\ncontentFace = { family = "User Content", fullName = "Content", postscriptName = "Content" }\n'
        )
        self.assertEqual(self.update().returncode, 0)
        fonts = self.read()["desktop"]["appearanceDarkChromeTheme"]["fonts"]
        self.assertNotIn("uiFace", fonts)
        self.assertNotIn("codeFace", fonts)
        self.assertEqual(fonts["content"], "User Content")
        self.assertEqual(fonts["contentFace"]["family"], "User Content")

    def test_new_file_is_private_and_updates_are_idempotent(self) -> None:
        """Avoid rewriting a converged file and preserve permissions."""
        self.assertEqual(self.update().returncode, 0)
        self.assertEqual(stat.S_IMODE(self.path.stat().st_mode), 0o600)
        self.path.chmod(0o640)
        before = self.path.read_bytes()
        inode = self.path.stat().st_ino
        self.assertEqual(self.update().returncode, 0)
        self.assertEqual(before, self.path.read_bytes())
        self.assertEqual(self.path.stat().st_ino, inode)
        self.assertEqual(stat.S_IMODE(self.path.stat().st_mode), 0o640)

    def test_invalid_toml_is_unchanged(self) -> None:
        """Reject malformed input without touching the file."""
        self.path.write_text('[desktop]\nbroken = "unterminated')
        before = self.path.read_bytes()
        self.assertNotEqual(self.update().returncode, 0)
        self.assertEqual(self.path.read_bytes(), before)

    def test_writable_symlink_is_preserved(self) -> None:
        """Update the symlink target without replacing the symlink."""
        target = self.path.with_name("actual.toml")
        target.write_text("[desktop]\ncustomPreference = true\n")
        self.path.symlink_to(target)
        self.assertEqual(self.update().returncode, 0)
        self.assertTrue(self.path.is_symlink())
        self.assertTrue(self.read()["desktop"]["customPreference"])


if __name__ == "__main__":
    unittest.main()
