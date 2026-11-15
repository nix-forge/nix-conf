{ inputs, ... }: {
  perSystem = { pkgs, ... }: {
    packages.desktop-nixos-anywhere =
      (import ../../../../overlays/temporary { inherit inputs pkgs; }).apply
        "nixos-anywhere-ssh-host-check"
        inputs.nixos-anywhere.packages.${pkgs.stdenv.hostPlatform.system}.default;
  };
}
