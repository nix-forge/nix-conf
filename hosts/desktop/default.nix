{
  self,
  tree,
  lib,
  inputs,
  ...
}:
lib.cust.mkHost {
  hostName = "desktop";
  system = "x86_64-linux";
  nixpkgs = inputs.nixpkgs;
  nixpkgsArgs = {
    config.allowUnfree = true;
  };
  stateVersion = "24.05";

  specialArgs = {
    host = {
      logicalProcessors = 16; # run nproc
    };
  };

  nixosModules = with tree.hosts.shared; [
    ## Base
    base.nix-settings
    base.nix-registry
    base.base
    base.kernel
    base.packages
    ./users.nix

    ## Boot
    boot.grub.default
    boot.grub.dual-boot
    ./hardware/kernel-modules.nix
    # plymouth
    # grub theme

    ## Locale
    ./timezone.nix
    locale.timesync
    locale.fonts
    # keyboard
    # languages

    ## Hardware
    ./hardware/filesystems.nix
    ./hardware/gpu.nix
    ./hardware/cpu.nix
    hardware.zram
    hardware.networking
    # virtualization
    hardware.bluetooth
    # firmware
    hardware.pipewire
    # power management
    peripherals.mouse
    # gaming support

    ## Desktop Environments
    (desktop-envs.hyprland { useMainUser = true; })
    # desktop-envs.gnome
    # desktop-envs.plasma

    ## Display Managers
    # display-managers.greetd
    display-managers.gdm
    # display-managers.sddm

    ## Services
    services.disable-hibernate

    ## Theming
    stylix.base
    stylix.cursor
    stylix.fonts

    ## Other
    gaming.default
    # swaylock setup (replace with hyprlock)
    # keyring
    # polkit

    ## Environment Variables
    { environment.sessionVariables = lib.cust.env.wayland.all; }
  ];

  overlays = [
    inputs.nur.overlay
    inputs.vscode-extensions.overlays.default
    inputs.nixd.overlays.default

    # inputs.nixpkgs-wayland.overlays.default

    inputs.birdos.overlays.allowUnfree
    inputs.birdos.overlays.ttf-ms-win11
  ];

  # inherit function arguments
  inherit
    inputs
    lib
    tree
    self
    ;
}
