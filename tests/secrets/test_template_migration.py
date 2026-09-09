"""Exercise config semantics, rejection, and real nix-seal encrypted rendering."""

from __future__ import annotations

import json
import os
import runpy
import subprocess
import tempfile
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

import tomllib

ROOT = Path(__file__).resolve().parents[2]
MIGRATION = runpy.run_path(str(ROOT / "scripts/migrate-secret-templates.py"))
PUBLIC_KEY = "ssh-ed25519 public-fixture-key"
RUNTIME = {
    "owner": str(os.getuid()),
    "group": str(os.getgid()),
    "mode": "0400",
    "restartUnits": [],
    "reloadUnits": [],
    "compatibilitySymlink": None,
}


class TemplateMigrationTests(unittest.TestCase):
    """Verify migration safety using disposable values and identities."""

    def test_authoring_preserves_relocated_ciphertext_sources(self) -> None:
        """Reviewing an old input cannot restore its retired storage directory."""
        source = "secrets/fixture/gitconfig-username.age"
        spec, _ = MIGRATION["_split_config"](
            source, b"[user]\n name = Fixture\n", {}, PUBLIC_KEY
        )
        moved = {
            **spec,
            "fields": {"git-user-name": {"source": "homes/shared/name.age"}},
        }
        MIGRATION["_retain_field_sources"](spec, {source: moved})
        self.assertEqual(spec["fields"], moved["fields"])
        with self.assertRaises(MIGRATION["MigrationError"]):
            MIGRATION["_retain_field_sources"](spec, {source: {**moved, "fields": {}}})

    def test_local_inventory_updates_preserve_template_placement(self) -> None:
        """Authoring updates the owning template without recreating a central file."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            folder = root / "homes/shared/templates"
            folder.mkdir(parents=True)
            source = "secrets/fixture/gitconfig-username.age"
            spec, _ = MIGRATION["_split_config"](
                source, b"[user]\n name = Fixture\n", {}, PUBLIC_KEY
            )
            template = folder / "name.template"
            template.write_text(spec["content"])
            catalog = folder / "inventory.json"
            catalog.write_text(
                json.dumps({
                    source: {
                        key: value for key, value in spec.items() if key != "content"
                    }
                    | {"template": template.name}
                })
            )
            globals_ = MIGRATION["_read_inventory"].__globals__
            with patch.dict(
                globals_,
                {"ROOT": root, "INVENTORY_FILES": (catalog.relative_to(root),)},
            ):
                self.assertEqual(MIGRATION["_read_inventory"](), {source: spec})
                spec["content"] = "# Public configuration\n" + spec["content"]
                MIGRATION["_write_inventory"]({source: spec})
                self.assertEqual(template.read_text(), spec["content"])
                self.assertEqual(MIGRATION["_read_inventory"](), {source: spec})
                self.assertNotIn("content", json.loads(catalog.read_text())[source])
                before = catalog.read_bytes(), template.read_bytes()
                with self.assertRaises(MIGRATION["MigrationError"]):
                    MIGRATION["_write_inventory"]({source: spec, "unassigned": spec})
                self.assertEqual((catalog.read_bytes(), template.read_bytes()), before)
                self.assertFalse((root / "secrets/templates.json").exists())

    @staticmethod
    def split(
        name: str, text: str, emails: dict[str, str] | None = None
    ) -> tuple[dict[str, Any], dict[str, str]]:
        """Parse a test fixture.

        Returns:
            A public template and private fields.

        """
        return MIGRATION["_split_config"](
            f"secrets/{MIGRATION['HOME_SCOPE']}/{name}.age",
            text.encode(),
            emails or {},
            PUBLIC_KEY,
        )

    @staticmethod
    def render(spec: dict[str, Any], values: dict[str, str]) -> str:
        """Substitute test fields.

        Returns:
            Rendered test content.

        """
        text = spec["content"]
        for name, value in values.items():
            text = text.replace(MIGRATION["_marker"](name), value)
        return text

    def test_git_and_jj_share_identity_without_changing_git_value(self) -> None:
        """Git and jj share identity without changing git value."""
        original = "[user]\n    name = Test Person\n"
        spec, values = self.split("gitconfig-username", original)
        rendered = self.render(spec, values)
        for content in [original, rendered]:
            result = subprocess.run(
                ["git", "config", "--file", "/dev/stdin", "--get", "user.name"],
                input=content.encode(),
                capture_output=True,
                check=True,
                timeout=30,
            )
            self.assertEqual(result.stdout, b"Test Person\n")
        self.assertEqual(tomllib.loads(rendered)["user"]["name"], "Test Person")
        self.assertNotIn("Test Person", json.dumps(spec))

    def test_signer_namespaces_and_key_are_preserved(self) -> None:
        """Signer namespaces and key are preserved."""
        original = f'test@example.invalid namespaces="git" {PUBLIC_KEY}\n'
        spec, values = self.split(
            "git-allowedsigners", original, {"git-user-email": "test@example.invalid"}
        )
        self.assertEqual(self.render(spec, values), original)
        self.assertNotIn("test@example.invalid", json.dumps(spec))
        with self.assertRaises(MIGRATION["MigrationError"]):
            self.split(
                "git-allowedsigners",
                original.replace('namespaces="git"', 'namespaces="file"'),
                {"git-user-email": "test@example.invalid"},
            )

    def test_nix_and_ssh_preserve_semantics(self) -> None:
        """Nix and ssh preserve semantics."""
        for name, original in [
            ("nix-access-tokens", "access-tokens = github.com=fixture-value\n"),
            ("cornell-net-id-ssh-config", "User fixture-user\n"),
        ]:
            spec, values = self.split(name, original)
            self.assertEqual(self.render(spec, values), original)
            for value in values.values():
                self.assertNotIn(value, json.dumps(spec))

    def test_netrc_and_environment_preserve_values_and_drop_private_comments(
        self,
    ) -> None:
        """Netrc and environment preserve values and drop private comments."""
        for name, original in [
            (
                "flakehub-netrc",
                "machine flakehub.com login fixture-login password fixture-password\n",
            ),
            (
                "flakehub-netrc",
                "machine edge.cache.flakehub.com login fixture-login password fixture-password\n",
            ),
            ("service-runtime-environment", "API_TOKEN='fixture value'\nPORT=8788\n"),
        ]:
            spec, values = self.split(name, original)
            self.assertEqual(self.render(spec, values), original)
        spec, _ = self.split(
            "service-runtime-environment", "# private-canary\nAPI_TOKEN=fixture-value\n"
        )
        self.assertNotIn("private-canary", json.dumps(spec))

    def test_environment_names_and_values_are_private(self) -> None:
        """Bundle assignments without exposing application-specific names."""
        original = "PRIVATE_APP_PORT=8788\nPRIVATE_APP_TOKEN=private-canary\n"
        spec, values = self.split("service-runtime-environment", original)
        self.assertEqual(
            values,
            {"service-private-settings": original},
        )
        self.assertEqual(self.render(spec, values), original)
        for private in ["PRIVATE_APP", "8788", "private-canary"]:
            self.assertNotIn(private, json.dumps(spec))
        with self.assertRaises(MIGRATION["MigrationError"]):
            self.split(
                "service-runtime-environment",
                "PRIVATE_APP_PORT=8788\nPRIVATE_APP_PORT=8789\n",
            )

    def test_netrc_shares_credentials_and_rejects_mismatch(self) -> None:
        """Reuse two fields while rejecting distinct credentials or duplicate hosts."""
        first = "machine flakehub.com login fixture-login password fixture-password\n"
        second = (
            "machine api.flakehub.com login fixture-login password fixture-password\n"
        )
        spec, values = self.split("flakehub-netrc", first + second)
        self.assertEqual(set(values), {"flakehub-login", "flakehub-password"})
        self.assertEqual(self.render(spec, values), first + second)
        self.assertEqual(
            spec["fields"]["flakehub-login"]["source"],
            "secrets/ianhollow/shared/flakehub-login.age",
        )
        for changed in [
            second.replace("fixture-login", "another-login"),
            second.replace("fixture-password", "another-password"),
            first,
        ]:
            with self.assertRaises(MIGRATION["MigrationError"]):
                self.split("flakehub-netrc", first + changed)

    def test_reject_ambiguous_and_injected_input(self) -> None:
        """Reject ambiguous and injected input."""
        cases = [
            ("gitconfig-username", '[user]\nname = "quoted"\n'),
            (
                "gitconfig-useremail",
                "[user]\nemail = test@example.invalid\n[include]\npath=/tmp/extra\n",
            ),
            ("nix-access-tokens", "access-tokens = private-canary.invalid=fixture\n"),
            ("nix-access-tokens", "access-tokens = github.com=one github.com=two\n"),
            ("service-runtime-environment", "TOKEN=one\nTOKEN=two\n"),
            ("service-runtime-environment", "TOKEN={{nix-seal:unexpected}}\n"),
            (
                "flakehub-netrc",
                "machine private-canary.invalid login user password fixture\n",
            ),
        ]
        for name, text in cases:
            with (
                self.subTest(name=name),
                self.assertRaises(MIGRATION["MigrationError"]),
            ):
                self.split(name, text)

    def test_real_batch_encryption_and_nix_seal_rendering(self) -> None:
        """Real batch encryption and nix seal rendering."""
        # Independent disposable identity: no live identity or ciphertext read.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            key = root / "identity"

            def cli(*args: str | Path, data: bytes | None = None) -> bytes:
                result = subprocess.run(
                    ["nix-seal", *map(str, args)],
                    input=data,
                    capture_output=True,
                    check=False,
                    timeout=30,
                )
                if result.returncode:
                    raise subprocess.CalledProcessError(
                        result.returncode, result.args, stderr=result.stderr
                    )
                return result.stdout

            cli("key", "generate", "--identity-out", key)
            recipient = cli("key", "inspect", "--identity", key).decode().strip()
            spec, values = self.split(
                "service-runtime-environment",
                "PRIVATE_APP_TOKEN='fixture value'\nPRIVATE_APP_PORT=8788\n",
            )
            template = root / "public.template"
            template.write_text(spec["content"])
            plan = {
                "schema": "nix-seal.plan.v2",
                "identities": {
                    "admin": {"kind": "administrator", "public": recipient},
                    "release": {
                        "kind": "signer",
                        "public": "nix-seal-ed25519-v1:bGfuLIxQvDrT8IMpu931WWcILSKDrDmaCJ8oPFyT3X4=",
                    },
                },
                "groups": {},
                "targets": {},
                "approvalPolicies": {
                    "release": {"threshold": 1, "signers": ["release"]}
                },
                "backends": {},
                "generators": {},
                "secrets": {},
                "templates": {
                    "config": {
                        "source": str(template),
                        "runtime": RUNTIME,
                        "placeholders": {},
                    }
                },
            }
            for field in values:
                plan["secrets"][field] = {
                    "source": f"secrets/{field}.age",
                    "sourceCiphertextHash": "0" * 64,
                    "administrators": ["admin"],
                    "consumers": [],
                    "delivery": "rekeyed",
                    "approvalPolicy": "release",
                    "phase": "activation",
                    "lifecycle": {},
                    "runtime": RUNTIME,
                }
                plan["templates"]["config"]["placeholders"][field] = {
                    "secret": field,
                    "encoding": "utf8",
                }
            policy = root / "plan.json"
            policy.write_text(json.dumps(plan))
            mapping = root / "mapping.json"
            mapping.write_text(
                json.dumps({
                    "schema": "nix-seal.collection.v1",
                    "entries": [{"secret": field, "path": field} for field in values],
                })
            )
            cli(
                "secret",
                "batch",
                "--plan",
                policy,
                "--repository-root",
                root,
                "--identity",
                key,
                "--mapping",
                mapping,
                "--format",
                "json",
                data=json.dumps(values).encode(),
            )
            output = root / "rendered"
            for field, value in values.items():
                self.assertEqual(
                    cli(
                        "secret",
                        "reveal",
                        "--plan",
                        policy,
                        "--repository-root",
                        root,
                        "--identity",
                        key,
                        "--secret",
                        field,
                    ),
                    value.encode(),
                )
            cli(
                "template",
                "render",
                "--plan",
                policy,
                "--repository-root",
                root,
                "--identity",
                key,
                "--template",
                "config",
                "--output",
                output,
            )
            self.assertEqual(
                output.read_text(),
                "PRIVATE_APP_TOKEN='fixture value'\nPRIVATE_APP_PORT=8788\n",
            )
            self.assertEqual(output.stat().st_mode & 0o777, 0o600)
            self.assertNotIn(
                b"fixture value", next((root / "secrets").glob("*.age")).read_bytes()
            )
            with self.assertRaises(subprocess.CalledProcessError):
                cli(
                    "secret",
                    "batch",
                    "--plan",
                    policy,
                    "--repository-root",
                    root,
                    "--identity",
                    key,
                    "--mapping",
                    mapping,
                    "--format",
                    "json",
                    data=json.dumps(values).encode(),
                )


if __name__ == "__main__":
    unittest.main()
