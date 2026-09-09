{ inputs, myLib, ... }: {
  perSystem = { pkgs, ... }: {
    checks = pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux (
      import ../../tests/nix/noogle.nix { inherit pkgs inputs myLib; }
    );
  };
}
