{
  perSystem = { config, pkgs, ... }: {
    devShells.default = pkgs.mkShellNoCC {
      packages = with pkgs; [
        nh
        just
        config.packages.nix-seal
      ];
      shellHook = config.pre-commit.installationScript;
    };
  };
}
