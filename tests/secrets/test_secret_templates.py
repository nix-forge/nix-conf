"""Exercise template reconstruction and Jujutsu rollback with synthetic values."""

from __future__ import annotations

import copy
import runpy
import stat
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

import tomllib

ROOT = Path(__file__).resolve().parents[2]
MIGRATION = runpy.run_path(str(ROOT / "scripts/migrate-secret-templates.py"))
IDENTITY = runpy.run_path(
    str(ROOT / "modules/home/dev/scripts/write-jujutsu-identity.py")
)
PUBLIC_KEY = "ssh-ed25519 public-fixture-key"
HOME_VALUES = {"git-user-email": "fixture@example.invalid"}


class SecretTemplateTests(unittest.TestCase):
    """Only temporary fixtures and pure parsing helpers are exercised."""

    def test_supported_formats_preserve_configuration(self) -> None:
        """Whitespace normalization retains each format's effective values."""
        examples = {
            "gitconfig-username": "[user]\n name = Alice Example\n",
            "gitconfig-useremail": "[user]\n email = fixture@example.invalid\n",
            "cornell-net-id-ssh-config": "User   fixture123\n",
            "nix-access-tokens": "access-tokens=github.com=fixture gitlab.com=second\n",
            "git-allowedsigners": f'fixture@example.invalid namespaces="git" {PUBLIC_KEY}\n',
            "flakehub-netrc": "machine flakehub.com login fixture password value\n",
            "service-runtime-environment": '# comment\nFIXTURE_VALUE="with spaces"\n',
        }
        for name, content in examples.items():
            with self.subTest(name=name):
                source = f"secrets/example/{name}.age"
                data = content.encode()
                spec, values = MIGRATION["_split_config"](
                    source, data, HOME_VALUES, PUBLIC_KEY
                )
                MIGRATION["_verify_template"](source, data, spec, values)

    def test_changed_public_configuration_is_rejected(self) -> None:
        """Scalar round trips alone cannot detect a changed public Git section."""
        source = "secrets/example/gitconfig-useremail.age"
        data = b"[user]\n email = fixture@example.invalid\n"
        spec, values = MIGRATION["_split_config"](source, data, HOME_VALUES, PUBLIC_KEY)
        changed = copy.deepcopy(spec)
        changed["content"] = changed["content"].replace("[user]", "[core]")
        with self.assertRaisesRegex(
            MIGRATION["MigrationError"], "differs from the original"
        ):
            MIGRATION["_verify_template"](source, data, changed, values)

    def test_missing_and_undeclared_placeholders_are_rejected(self) -> None:
        """Every field must be declared and referenced before authoring."""
        source = "secrets/example/cornell-net-id-ssh-config.age"
        data = b"User fixture123\n"
        spec, values = MIGRATION["_split_config"](source, data, HOME_VALUES, PUBLIC_KEY)
        for content in ("User {{nix-seal:unknown}}\n", "User hardcoded\n"):
            with self.subTest(content=content):
                changed = copy.deepcopy(spec)
                changed["content"] = content
                with self.assertRaises(MIGRATION["MigrationError"]):
                    MIGRATION["_verify_template"](source, data, changed, values)

    def test_unsupported_git_escaping_is_rejected(self) -> None:
        """A value requiring a different escaping policy must receive review."""
        for value in (
            '"quoted"',
            "back\\slash",
            "line\nbreak",
            "hash#value",
            "semi;colon",
            "delete\x7f",
        ):
            with (
                self.subTest(value=value),
                self.assertRaises(MIGRATION["MigrationError"]),
            ):
                MIGRATION["_split_config"](
                    "secrets/example/gitconfig-username.age",
                    f"[user]\n name = {value}\n".encode(),
                    {},
                    PUBLIC_KEY,
                )

    def test_failed_reconstruction_prevents_batch_authoring(self) -> None:
        """No create command runs when reconstructed content does not match."""
        globals_ = MIGRATION["_migrate"].__globals__
        error = MIGRATION["MigrationError"]("fixture reconstruction failure")
        with (
            patch.dict(
                globals_,
                {
                    "_collect_plans": lambda _workspace: ({}, {}),
                    "_extract_fields": Mock(side_effect=error),
                },
            ),
            patch.dict(globals_, {"_author_fields": Mock()}),
            self.assertRaises(MIGRATION["MigrationError"]),
        ):
            try:
                MIGRATION["_migrate"](
                    Path("/unused-identity"), True, Path("/unused-workspace")
                )
            finally:
                globals_["_author_fields"].assert_not_called()

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


if __name__ == "__main__":
    unittest.main()
