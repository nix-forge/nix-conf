"""Check CI discovery and deployment policy with independent configurations."""

import json
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class CIInventoryTests(unittest.TestCase):
    """Exercise coverage policy through the real flake modules."""

    def test_deployment_exclusions_apply_only_to_the_owning_system(self) -> None:
        """Keep ordinary additions and same-named checks on other systems."""
        expression = """
                    let
                        lib = (builtins.getFlake ROOT).inputs.nixpkgs.lib;
                        fixture = import DEPLOY {
                            inputs = {
                                nixpkgs = { inherit lib; };
                                deploy-rs.lib.x86_64-linux.deployChecks = _: {
                                    host-only = null;
                                    new-deployment-check = null;
                                };
                            };
                            self = {
                                deploy = {};
                                checks = {
                                    x86_64-linux = {
                                        ordinary = null;
                                        newly-added = null;
                                        host-only = null;
                                        new-deployment-check = null;
                                    };
                                    aarch64-darwin = { host-only = null; ordinary = null; };
                                };
                            };
                        };
                    in builtins.mapAttrs (_: builtins.attrNames) fixture.flake.ciChecks
        """.replace("ROOT", json.dumps(str(ROOT))).replace(
            "DEPLOY", str(ROOT / "flake/deploy.nix")
        )
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
                lib = (builtins.getFlake ROOT).inputs.nixpkgs.lib;
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
        """.replace("ROOT", json.dumps(str(ROOT))).replace(
            "MODULE", str(ROOT / "flake/dev/configurations.nix")
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


if __name__ == "__main__":
    unittest.main()
