{ self, lib, ... }: {
  perSystem = { pkgs, system, ... }: {
    checks = lib.optionalAttrs (system == "x86_64-linux") {
      desktop-usbguard-rules =
        let
          rules = pkgs.writeText "desktop-usbguard.rules" self.nixosConfigurations.desktop.config.services.usbguard.rules;
        in
        pkgs.runCommand "desktop-usbguard-rules-check" { } ''
          ${pkgs.python3}/bin/python ${../../tests/nix/check-desktop-usbguard-rules.py} ${rules}
          touch "$out"
        '';
    };
  };
}
