"""Exercise the production theme importer against changing target inventories."""

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

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
        expression = """
            let
                inputs = (builtins.getFlake ROOT).inputs;
                lib = inputs.nixpkgs.lib;
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
        """.replace("ROOT", json.dumps(str(ROOT))).replace(
            "MODULE", json.dumps(str(root / "home.nix"))
        )
        result = subprocess.run(
            ["nix", "eval", "--impure", "--json", "--expr", expression],
            check=True,
            capture_output=True,
            text=True,
        )
        return json.loads(result.stdout)


if __name__ == "__main__":
    unittest.main()
