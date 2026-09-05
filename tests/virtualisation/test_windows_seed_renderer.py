"""Unit tests for the volatile Windows installer seed renderer."""

from __future__ import annotations

import importlib.util
import os
import stat
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from types import ModuleType


def load_renderer() -> ModuleType:
    """Load the standalone renderer from the path used by the Nix check.

    Returns:
        The imported renderer module.

    Raises:
        RuntimeError: If Python cannot construct an import specification.

    """
    source = os.environ.get("WINDOWS_VM_SEED_RENDERER")
    if source is None:
        source = str(
            Path(__file__).parents[2]
            / "modules/nixos/virtualisation/scripts/windows-vm-render-seed.py"
        )
    specification = importlib.util.spec_from_file_location(
        "windows_vm_seed_renderer", source
    )
    if specification is None or specification.loader is None:
        message = "could not load the Windows VM seed renderer"
        raise RuntimeError(message)
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


RENDERER = load_renderer()


class WindowsSeedRendererTests(unittest.TestCase):
    """Exercise secret validation, escaping, and output permissions."""

    @staticmethod
    def write_secret(root: Path, content: str, mode: int = 0o600) -> Path:
        """Create a credential fixture.

        Returns:
            The restricted fixture path.

        """
        path = root / "password"
        path.write_text(content, encoding="utf-8")
        path.chmod(mode)
        return path

    def test_renders_two_xml_escaped_passwords_and_private_credential(self) -> None:
        """Escape both answer-file values and restrict both output files."""
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            template = root / "Autounattend.xml.in"
            template.write_text(
                "<root><first>__WINDOWS_ADMINISTRATOR_PASSWORD_XML__</first>"
                "<second>__WINDOWS_ADMINISTRATOR_PASSWORD_XML__</second></root>",
                encoding="utf-8",
            )
            password = "Long&Strong<Password>42!"
            password_file = self.write_secret(root, f"{password}\n")
            answer_file = root / "output" / "Autounattend.xml"
            credential_file = root / "output" / "administrator-password.txt"

            RENDERER.render(template, answer_file, credential_file, password_file)

            document = ET.parse(answer_file)
            self.assertEqual(
                [node.text for node in document.getroot()], [password, password]
            )
            self.assertEqual(
                credential_file.read_text(encoding="utf-8"), f"{password}\n"
            )
            self.assertFalse(answer_file.read_bytes().startswith(b"\xef\xbb\xbf"))
            self.assertTrue(answer_file.read_bytes().isascii())
            self.assertEqual(stat.S_IMODE(answer_file.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(credential_file.stat().st_mode), 0o600)

    def test_rejects_group_readable_password_file(self) -> None:
        """Reject credential inputs that another host account could read."""
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            password_file = self.write_secret(
                root, "LongEnoughPassword42!\n", mode=0o640
            )

            with self.assertRaisesRegex(ValueError, "group or other"):
                RENDERER.read_password(password_file)

    def test_rejects_multiline_password(self) -> None:
        """Reject input that could smuggle an additional credential line."""
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            password_file = self.write_secret(
                root, "LongEnoughPassword42!\nsecond-line\n"
            )

            with self.assertRaisesRegex(ValueError, "exactly one line"):
                RENDERER.read_password(password_file)

    def test_rejects_whitespace_and_native_option_prefixes(self) -> None:
        """Keep the native Autologon argument sequence unambiguous."""
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            password_file = self.write_secret(root, "Long Password42!\n")
            with self.assertRaisesRegex(ValueError, "whitespace"):
                RENDERER.read_password(password_file)

            password_file.write_text("-LongPassword42!\n", encoding="utf-8")
            password_file.chmod(0o600)
            with self.assertRaisesRegex(ValueError, "begin with a letter or digit"):
                RENDERER.read_password(password_file)

    def test_requires_three_password_character_categories(self) -> None:
        """Enforce the host helper's password-category requirement again."""
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            password_file = self.write_secret(root, "onlylowercasepassword\n")

            with self.assertRaisesRegex(ValueError, "three character categories"):
                RENDERER.read_password(password_file)

    def test_rejects_non_ascii_password(self) -> None:
        """Keep Setup, XML, PowerShell, and native argument handling predictable."""
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            password_file = self.write_secret(root, "LongPassword42!é\n")

            with self.assertRaisesRegex(ValueError, "printable ASCII"):
                RENDERER.read_password(password_file)

    def test_rejects_symlink_password_file(self) -> None:
        """Refuse to follow a swapped or redirected credential path."""
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            target = self.write_secret(root, "LongEnoughPassword42!\n")
            symlink = root / "password-link"
            symlink.symlink_to(target)

            with self.assertRaisesRegex(ValueError, "not a symlink"):
                RENDERER.read_password(symlink)

    def test_requires_exactly_two_template_tokens(self) -> None:
        """Fail closed if the public answer template's secret contract changes."""
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            template = root / "Autounattend.xml.in"
            template.write_text(
                "<root>__WINDOWS_ADMINISTRATOR_PASSWORD_XML__</root>", encoding="utf-8"
            )
            password_file = self.write_secret(root, "LongEnoughPassword42!\n")

            with self.assertRaisesRegex(
                ValueError, "must contain the password token twice"
            ):
                RENDERER.render(
                    template,
                    root / "Autounattend.xml",
                    root / "administrator-password.txt",
                    password_file,
                )


if __name__ == "__main__":
    unittest.main()
