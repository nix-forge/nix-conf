{ self, ... }: {
  perSystem =
    {
      lib,
      pkgs,
      system,
      ...
    }:
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        desktop-ca-bundle = import ../../tests/nix/ca-bundle.nix {
          inherit pkgs;
          desktopConfig = self.nixosConfigurations.desktop.config;
        };
      };
    };
}
