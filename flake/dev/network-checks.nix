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
        desktop-network-carrier-policy =
          let
            desktop = self.nixosConfigurations.desktop.config;
            wireless = desktop.systemd.network.networks."30-wireless-networks";
            unit =
              pkgs.writeText "30-wireless-networks.network"
                desktop.systemd.network.units."30-wireless-networks.network".text;
          in
          assert wireless.networkConfig.IgnoreCarrierLoss == false;
          pkgs.runCommand "desktop-network-carrier-policy-check" { nativeBuildInputs = [ pkgs.gnugrep ]; } ''
            grep -Fx 'IgnoreCarrierLoss=false' ${unit}
            touch "$out"
          '';
      };
    };
}
