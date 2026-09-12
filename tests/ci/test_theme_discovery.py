"""Exercise the production theme importer against changing target inventories."""

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import pytest

pytestmark = [pytest.mark.nix_daemon, pytest.mark.usefixtures("isolated_git")]

ROOT = Path(__file__).resolve().parents[2]


class ThemeDiscoveryTests(unittest.TestCase):
    """Adding, moving and removing targets must update the imported modules."""

    def test_target_inventory_changes(self) -> None:
        """Import new and moved exports, omitting deleted and unrelated classes."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            shutil.copyfile(ROOT / "modules/shared/stylix/home.nix", root / "home.nix")
            targets = root / "targets"
            alpha = targets / "alpha" / "home.nix"
            beta = targets / "beta" / "home.nix"
            for path, value in [(alpha, "alpha"), (beta, "beta")]:
                path.parent.mkdir(parents=True)
                path.write_text(
                    "{ homeManager.config.discovered = [ "
                    + json.dumps(value)
                    + " ]; }\n"
                )
            (targets / "beta" / "system.nix").write_text(
                '{ nixos = throw "wrong platform imported"; }\n'
            )
            (targets / "beta" / "helper.nix").write_text(
                '{ render = _: throw "rendering helper evaluated"; }\n'
            )
            self.assertCountEqual(self._discover(root), ["alpha", "beta"])
            gamma = targets / "gamma" / "nested" / "home.nix"
            gamma.parent.mkdir(parents=True)
            gamma.write_text('{ homeManager.config.discovered = [ "gamma" ]; }\n')
            self.assertCountEqual(self._discover(root), ["alpha", "beta", "gamma"])
            alpha.unlink()
            beta.rename(beta.with_name("renamed.nix"))
            self.assertCountEqual(self._discover(root), ["beta", "gamma"])

    @staticmethod
    def _discover(root: Path) -> list[str]:
        expression = (
            """
            let
                lib = import NIXPKGS_LIB;
                inputs.nix-config-framework.lib = import FRAMEWORK_LIB { inherit lib; };
                evaluated = lib.evalModules {
                    specialArgs = { inherit inputs; };
                    modules = [
                        (import MODULE).homeManager
                        { options.discovered = lib.mkOption {
                                type = lib.types.listOf lib.types.str;
                                default = [ ];
                            };
                        }
                    ];
                };
            in evaluated.config.discovered
        """
            .replace("NIXPKGS_LIB", json.dumps(os.environ["NIX_TEST_NIXPKGS"] + "/lib"))
            .replace(
                "FRAMEWORK_LIB", json.dumps(os.environ["NIX_TEST_FRAMEWORK"] + "/lib")
            )
            .replace("MODULE", json.dumps(str(root / "home.nix")))
        )
        result = subprocess.run(
            ["nix", "eval", "--impure", "--json", "--expr", expression],
            check=True,
            capture_output=True,
            text=True,
        )
        return json.loads(result.stdout)
