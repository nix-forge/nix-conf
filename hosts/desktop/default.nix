{
  tree,
  hostname,
  lib,
  inputs,
  ...
}:
rec {
  system = "x86_64-linux";
  nixpkgsArgs = {
    config.allowUnfree = true;
  };
  modules = with (tree.hosts.${hostname} // tree.hosts.${hostname}.hardware // tree.configs.os); [
    ## Base
    base.nix-settings
    base.nix-registry
    base.base
    base.kernel
    base.packages
    users

    ## Boot
    boot.generic
    boot.grub.default
    boot.grub.dual-boot
    kernel-modules
    # plymouth

    ## Locale
    timezone
    locale.timesync
    locale.fonts
    # keyboard

    ## Hardware
    filesystems
    gpu
    cpu
    power
    audio
    hardware.zram
    hardware.networking
    hardware.bluetooth
    hardware.tpm
    hardware.firmware
    hardware.sound.default
    hardware.ssd
    hardware.storage
    peripherals.mouse
    gaming.default

    ## Virtualization
    virtualisation.docker
    virtualisation.libvirt

    ## Desktop Environments
    # desktop-envs.gnome
    # desktop-envs.plasma
    desktop-envs.hyprland

    ## Display Managers
    # display-managers.greetd
    display-managers.gdm
    # display-managers.sddm

    ## Security
    security.default

    ## Services
    services.runners
    services.disable-hibernate

    # Programs
    # programs.ccache

    ## Theming
    stylix.base
    stylix.cursor
    stylix.fonts

    ## Server
    server.minecraft.default

    ## Environment Variables
    { environment.sessionVariables = lib.cust.env.wayland.all; }
  ];

  overlays = [
    inputs.nur.overlay
    inputs.vscode-extensions.overlays.default
    inputs.nixd.overlays.default
  ];
}
