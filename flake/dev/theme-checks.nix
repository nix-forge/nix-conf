{ inputs, myLib, ... }: {
  perSystem = { pkgs, ... }: {
    checks.theme-targets = import ../../tests/nix/theme-targets.nix { inherit inputs myLib pkgs; };
    checks.noctalia-palettes = import ../../tests/nix/noctalia-palettes.nix { inherit inputs pkgs; };
  };
}
