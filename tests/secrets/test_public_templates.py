"""Render the current public files using disposable ciphertext and identities."""

from __future__ import annotations

import json
import netrc
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path
from typing import TYPE_CHECKING

import tomllib

if TYPE_CHECKING:
    from typing import Any

ROOT = Path(__file__).resolve().parents[2]


def cli(*args: str | Path, data: bytes | None = None) -> bytes:
    """Run the real CLI with bounded fixture input and captured output.

    Returns:
        The command's standard output.

    """
    return subprocess.run(
        ["nix-seal", *map(str, args)],
        input=data,
        capture_output=True,
        check=True,
        timeout=30,
    ).stdout


class PublicTemplateTests(unittest.TestCase):
    """Exercise actual public syntax without a maintained template inventory."""

    def test_current_templates_render_and_parse(self) -> None:
        """Encrypted fields produce valid application config and private outputs."""
        values = {
            "git-user-name": "Example Person",
            "git-user-email": "fixture@example.invalid",
            "git-user-email-cornell": "academic@example.invalid",
            "git-user-email-github": "code@example.invalid",
            "cornell-net-id": "fixture123",
            "nix-token-github-com": "fixture-token",
            "flakehub-login": "fixture-login",
            "flakehub-password": "fixture-password",
            "service-private-settings": "EXAMPLE_TOKEN='fixture value'\nEXAMPLE_PORT=8788\n",
        }
        aliases = {"name": "git-user-name", "email": "git-user-email"}
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            key = root / "identity"
            cli("key", "generate", "--identity-out", key)
            recipient = cli("key", "inspect", "--identity", key).decode().strip()
            runtime = {
                "owner": str(os.getuid()),
                "group": str(os.getgid()),
                "mode": "0400",
                "restartUnits": [],
                "reloadUnits": [],
                "compatibilitySymlink": None,
            }
            # JSON here is generated wire-format test data, never a source
            # configuration file or a parallel inventory maintained by users.
            plan: dict[str, Any] = {
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
                "secrets": {
                    name: {
                        "source": f"secrets/{name}.age",
                        "sourceCiphertextHash": "0" * 64,
                        "administrators": ["admin"],
                        "consumers": [],
                        "delivery": "rekeyed",
                        "approvalPolicy": "release",
                        "phase": "activation",
                        "lifecycle": {},
                        "runtime": runtime,
                    }
                    for name in values
                },
                "templates": {},
            }
            sources = sorted((ROOT / "compiled-templates").glob("*.template"))
            self.assertTrue(sources)
            for source in sources:
                names = re.findall(r"\{\{nix-seal:([a-z0-9_.-]+)}}", source.read_text())
                self.assertTrue(names, source.name)
                self.assertNotIn(source.stem, plan["templates"])
                bindings = {name: aliases.get(name, name) for name in names}
                self.assertTrue(set(bindings.values()) <= values.keys())
                plan["templates"][source.stem] = {
                    "source": str(source),
                    "runtime": runtime,
                    "placeholders": {
                        name: {"secret": field, "encoding": "utf8"}
                        for name, field in bindings.items()
                    },
                }
            policy = root / "generated-plan.json"
            policy.write_text(json.dumps(plan))
            mapping = root / "generated-mapping.json"
            mapping.write_text(
                json.dumps({
                    "schema": "nix-seal.collection.v1",
                    "entries": [{"secret": name, "path": name} for name in values],
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
                    "service-private-settings",
                ).decode(),
                values["service-private-settings"],
            )
            cli("template", "check", "--plan", policy)
            rendered = {}
            for source in sources:
                output = root / source.stem
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
                    source.stem,
                    "--output",
                    output,
                )
                rendered[source.stem] = output.read_text()
                self.assertEqual(output.stat().st_mode & 0o777, 0o600)
                self.assertNotIn("{{nix-seal:", rendered[source.stem])
            self._assert_application_config(root, values, rendered)

    def _assert_application_config(
        self, root: Path, values: dict[str, str], rendered: dict[str, str]
    ) -> None:
        """Check the application meanings of the rendered fixture files."""
        for name, field in (
            ("gitconfig-username", "name"),
            ("gitconfig-useremail", "email"),
            ("gitconfig-useremail-cornell", "email"),
            ("gitconfig-useremail-github", "email"),
        ):
            expected = values["git-user-" + name.removeprefix("gitconfig-user")]
            self.assertEqual(tomllib.loads(rendered[name])["user"][field], expected)
            actual = (
                subprocess
                .run(
                    [
                        "git",
                        "config",
                        "--file",
                        str(root / name),
                        "--get",
                        f"user.{field}",
                    ],
                    capture_output=True,
                    check=True,
                    timeout=30,
                )
                .stdout.decode()
                .strip()
            )
            self.assertEqual(actual, expected)
        self.assertEqual(
            tomllib.loads(rendered["jujutsu-identity"])["user"],
            {
                "name": values["git-user-name"],
                "email": values["git-user-email"],
            },
        )
        self.assertEqual(rendered["cornell-net-id-ssh-config"], "User fixture123\n")
        self.assertEqual(
            rendered["nix-access-tokens"],
            "access-tokens = github.com=fixture-token\n",
        )
        machines = netrc.netrc(str(root / "flakehub-netrc")).hosts
        self.assertEqual(
            set(machines),
            {
                "flakehub.com",
                "api.flakehub.com",
                "edge.cache.flakehub.com",
                "cache.flakehub.com",
            },
        )
        self.assertTrue(
            all(
                auth == ("fixture-login", "", "fixture-password")
                for auth in machines.values()
            )
        )
        signers = rendered["git-allowedsigners"].splitlines()
        self.assertEqual(
            len(signers),
            len([name for name in values if name.startswith("git-user-email")]),
        )
        self.assertTrue(
            all(' namespaces="git" ssh-ed25519 ' in line for line in signers)
        )
        signing_key = (
            (ROOT / "homes/macbook-pro-m4/local/nix-seal/identity.pub")
            .read_text()
            .strip()
        )
        self.assertTrue(all(line.endswith(signing_key) for line in signers))
        self.assertNotIn("{{public:", rendered["git-allowedsigners"])


if __name__ == "__main__":
    unittest.main()
