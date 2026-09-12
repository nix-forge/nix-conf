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

    def test_deployment_exclusions_apply_only_to_the_owning_system(self) -> None:
        """Keep ordinary additions and same-named checks on other systems."""
        expression = """
                    let
                        lib = import NIXPKGS_LIB;
                        fixture = import DEPLOY {
                            myLib = {};
                            inputs = {
                                nixpkgs = { inherit lib; };
                                deploy-rs.lib.x86_64-linux.deployChecks = _: {
                                    host-only = null;
                                    new-deployment-check = null;
                                };
                            };
                            self = {
                                deploy = {};
                                lintChecks.x86_64-linux = { new-portable-check = null; };
                                checks = {
                                    x86_64-linux = {
                                        ordinary = null;
                                        newly-added = null;
                                        new-portable-check = null;
                                        host-only = null;
                                        new-deployment-check = null;
                                    };
                                    aarch64-darwin = { host-only = null; ordinary = null; };
                                };
                            };
                        };
                    in builtins.mapAttrs (_: builtins.attrNames) fixture.flake.ciChecks
        """.replace(
            "NIXPKGS_LIB", json.dumps(os.environ["NIX_TEST_NIXPKGS"] + "/lib")
        ).replace("DEPLOY", str(ROOT / "flake/deploy.nix"))
        result = json.loads(
            subprocess.check_output(
                ["nix", "eval", "--impure", "--json", "--expr", expression], text=True
            )
        )
        self.assertEqual(
            result,
            {
                "x86_64-linux": ["newly-added", "ordinary"],
                "aarch64-darwin": ["host-only", "ordinary"],
            },
        )

    def test_configurations_follow_additions_and_removals_without_building_hosts(
        self,
    ) -> None:
        """Discover host checks while leaving foreign closures unevaluated."""
        expression = """
            let
                lib = import NIXPKGS_LIB;
                closure = builtins.derivation {
                    name = "configuration-fixture";
                    system = "x86_64-linux";
                    builder = "/never-executed";
                };
                evaluate = names:
                    let
                        module = import MODULE {
                            self = {
                                nixosConfigurations = builtins.listToAttrs (map (name: {
                                    inherit name;
                                    value = {
                                        pkgs.stdenv.hostPlatform.system = "x86_64-linux";
                                        config.system.build.toplevel = closure;
                                    };
                                }) names);
                                darwinConfigurations.foreign = {
                                    pkgs.stdenv.hostPlatform.system = "aarch64-darwin";
                                    system = throw "foreign closure was evaluated";
                                };
                            };
                        };
                        checks = (module.perSystem {
                            inherit lib;
                            system = "x86_64-linux";
                            pkgs.runCommand = _: attrs: _: attrs;
                        }).checks;
                    in builtins.mapAttrs (_: check: {
                        report = builtins.fromJSON check.report;
                        hasContext = builtins.hasContext check.report;
                    }) checks;
            in {
                before = evaluate [ "first" ];
                added = evaluate [ "first" "new" ];
                removed = evaluate [ "new" ];
            }
        """.replace(
            "NIXPKGS_LIB", json.dumps(os.environ["NIX_TEST_NIXPKGS"] + "/lib")
        ).replace("MODULE", str(ROOT / "flake/dev/configurations.nix"))
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
