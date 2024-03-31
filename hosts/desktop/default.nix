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
    ## Base
    base.nix-settings
    # nix-registry
    ./users.nix
    # xdg

    ## Boot
    boot.grub.default
    boot.grub.dual-boot
    # kernel modules
    # plymouth
    # grub theme

    ## Loclaization
    # time
    # keyboard
    # language

    ## Hardware
    ./filesystems.nix
    zram
    # networking
    # virtualization
    # bluetooth
    # firmware
    # pipewire
    # GPU
    # CPU
    # power management
    # pheripherals (mouse, trackpad, etc)
    # gaming support

    ## Input
    # fonts
    # fcitx

    ## Desktop Environments
    (desktop-envs.hyprland {useMainUser = true;})
    # gnome
    # plasma

    ## Display Manager
    # greetd
    # gdm
    # sddm

    # Other
    # swaylock setup (replace with hyprlock)
  ];

  overlays = [];
}
