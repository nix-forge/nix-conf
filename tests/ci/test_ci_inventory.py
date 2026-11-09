"""Check CI discovery and deployment policy with independent configurations."""

import json
import os
import subprocess
import unittest
from pathlib import Path

import pytest

pytestmark = [pytest.mark.nix_daemon, pytest.mark.usefixtures("isolated_git")]

ROOT = Path(__file__).resolve().parents[2]


class CIInventoryTests(unittest.TestCase):
    """Exercise coverage policy through the real flake modules."""

    def test_hosted_runner_exclusions_apply_on_every_system(self) -> None:
        """Keep ordinary additions while excluding workstation checks everywhere."""
        expression = (
            (Path(__file__).with_name("fixtures") / "hosted-check-selection.nix.in")
            .read_text(encoding="utf-8")
            .replace("NIXPKGS_LIB", json.dumps(os.environ["NIX_TEST_NIXPKGS"] + "/lib"))
            .replace("DEPLOY", str(ROOT / "hosts/shared/local/flake/deploy.nix"))
        )
        result = json.loads(
            subprocess.check_output(
                ["nix", "eval", "--impure", "--json", "--expr", expression], text=True
            )
        )
        self.assertEqual(
            result,
            {
                "x86_64-linux": [
                    "cache-policy",
                    "git-email-privacy",
                    "newly-added",
                    "ordinary",
                    "python-tests",
                    "secret-templates",
                ],
                "aarch64-darwin": [
                    "host-only",
                    "ordinary",
                    "python-tests",
                ],
                "aarch64-linux": ["ordinary"],
            },
        )

    def test_configurations_follow_additions_and_removals_without_building_hosts(
        self,
    ) -> None:
        """Discover host checks while leaving foreign closures unevaluated."""
        expression = (
            (Path(__file__).with_name("fixtures") / "configuration-inventory.nix.in")
            .read_text(encoding="utf-8")
            .replace("NIXPKGS_LIB", json.dumps(os.environ["NIX_TEST_NIXPKGS"] + "/lib"))
            .replace("MODULE", str(ROOT / "flake/dev/configurations.nix"))
        )
        result = json.loads(
            subprocess.check_output(
                ["nix", "eval", "--impure", "--json", "--expr", expression], text=True
            )
        )
        self.assertEqual(
            set(result["before"]),
            {"darwin-configuration-foreign", "nixos-configuration-first"},
        )
        self.assertEqual(
            set(result["added"]) - set(result["before"]), {"nixos-configuration-new"}
        )
        self.assertNotIn("nixos-configuration-first", result["removed"])
        for checks in result.values():
            for check in checks.values():
                self.assertFalse(check["hasContext"])
                report = check["report"]
                if report["native"]:
                    self.assertTrue(report["drvPath"].endswith(".drv"))
                else:
                    self.assertIsNone(report["drvPath"])
