"""Check deployment exclusions without evaluating any host configuration."""

import json
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class CIInventoryTests(unittest.TestCase):
    """Exercise coverage policy through the real deployment module."""

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


if __name__ == "__main__":
    unittest.main()
