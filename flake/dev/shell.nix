{
  perSystem = { config, pkgs, ... }: {
    devShells.default = pkgs.mkShellNoCC {
      packages = with pkgs; [
        nh
        just
      ];
      shellHook = config.pre-commit.installationScript;
    };
  };
}
