{ inputs, myLib, ... }: {
  perSystem = { pkgs, ... }: {
    checks = {
      theme-targets = import ../../tests/nix/theme-targets.nix { inherit inputs myLib pkgs; };
      noctalia-palettes = import ../../tests/nix/noctalia-palettes.nix { inherit inputs pkgs; };
    }
    // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
      gtk-polarity = import ../../tests/nix/gtk-polarity.nix { inherit inputs pkgs; };
    };
  };
}
