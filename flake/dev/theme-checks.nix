{ inputs, myLib, ... }: {
  perSystem = { pkgs, ... }: {
    checks.theme-targets = import ../../tests/nix/theme-targets.nix { inherit inputs myLib pkgs; };
  };
}
