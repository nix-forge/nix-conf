{
  tree,
  hostname,
  inputs,
  ...
}:
{
  system = "x86_64-linux";
  nixpkgsArgs = {
    config = {
      allowUnfree = true;
      cudaSupport = true;
    };
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
    boot.grub
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
    # kernel-patches
    power
    audio
    monitor
    networking
    hardware.zram
    hardware.networking
    hardware.bluetooth
    hardware.tpm
    hardware.firmware
    hardware.sound
    hardware.ssd
    hardware.storage

    ## Virtualization
    virtualisation.docker
    virtualisation.libvirt

    ## Desktop Environments
    # desktop-envs.gnome
    # desktop-envs.plasma
    desktop-envs.hyprland
    # desktop-envs.cosmic

    ## Display Managers
    # display-managers.greetd
    display-managers.gdm
    # display-managers.sddm

    ## Security
    security

    ## Services
    services.runners
    services.lid-switch

    # Programs
    # TODO: add neovim base config and better config in home-manager

    ## Theming
    stylix.base
    stylix.cursor
    stylix.fonts

    ## Server
    # server.minecraft

    ## Environment Variables
    { environment.sessionVariables = tree.configs.shared.env.wayland.default; }
  ];

  overlays = [
    # inputs.nur.overlay.default
    inputs.vscode-extensions.overlays.default
    inputs.nixd.overlays.default
  ];
}
