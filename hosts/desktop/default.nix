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
  nixpkgsArgs = {allowUnfree = true;};
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

    # Desktop Environments
    (desktop-envs.hyprland {useMainUser = true;})

    ./filesystems.nix
  ];

  overlays = [];

  systemUsers = let
    inherit (lib.cust) mkUser;
    homeConfigs = tree.home.configs;
  in {
    rootInitialPassword = "password";
    mainUser = {
      username = "ianmh";
      name = "Ian Holloway";
      extraGroups = ["wheel" "audio" "video"];
      initialPassword = "password";
      homeModules = homeConfigs.desktop.modules {inherit tree;};
    };
    otherUsers = [
      {
        username = "guest";
        name = "Guest";
        initialPassword = "password";
        homeModules = [];
      }
    ];
  };
}
