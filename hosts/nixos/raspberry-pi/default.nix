{ inputs, modules, ... }: {
  system = "aarch64-linux";
  hostName = "raspberry-pi";
  homes.ianmh.config = "ianmh@raspberry-pi";
  specialArgs.nixos-raspberrypi = inputs.nixos-raspberrypi;
  modules = [
    modules.ssh
    modules.nixSeal
    inputs.nix-homelab.nixosModules.iot
    inputs.nix-homelab.nixosModules.lanHttps
    inputs.disko.nixosModules.disko
    (import ../../../modules/shared/cache.nix).nixos
    inputs.nixos-raspberrypi.lib.inject-overlays
    inputs.nixos-raspberrypi.nixosModules.raspberry-pi-4.base

  ];
}
