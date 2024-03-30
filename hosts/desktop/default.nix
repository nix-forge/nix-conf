{
  self,
  tree,
  lib,
  inputs,
  ...
}:
lib.cust.mkHost {
  inherit inputs lib tree self;
  system = "x86_64-linux";
  nixpkgs = inputs.nixpkgs;
  nixpkgsArgs = {config.allowUnfree = true;};
  stateVersion = "24.05";

  specialArgs = {
    host = {
      name = "desktop";
      logicalProcessors = 16; # run nproc
    };
  };

  nixosModules = with tree.hosts.shared; [
    # Base
    nix-settings

    # Boot
    boot.grub.default
    boot.grub.dual-boot

    # Hardware
    zram

    # Desktop Environments
    (desktop-envs.hyprland {useMainUser = true;})

    ./filesystems.nix
    ./users.nix
  ];

  overlays = [];
}
