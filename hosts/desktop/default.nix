{
  tree,
  hostname,
  lib,
  inputs,
  ...
}:
{
  system = "x86_64-linux";
  nixpkgsArgs = {
    config.allowUnfree = true;
  };

  # TODO: rewrite map function to import everything if no default and is dir
  modules = builtins.map (x: if x ? "default" then x.default else x) (
    with (tree.hosts.${hostname} // tree.hosts.${hostname}.hardware // tree.configs.os);
    [
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
      hardware.zram
      hardware.networking
      hardware.bluetooth
      hardware.tpm
      hardware.firmware
      hardware.sound
      hardware.ssd
      hardware.storage
      peripherals.mouse
      gaming

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
      services.disable-hibernate
      services.earlyoom

      # Programs
      # TODO: add neovim base config and better config in home-manager

      ## Theming
      stylix.base
      stylix.cursor
      stylix.fonts

      ## Server
      # server.minecraft

      ## Environment Variables
      { environment.sessionVariables = lib.cust.env.wayland.all; }
    ]
  );

  overlays = [
    inputs.nur.overlay
    inputs.vscode-extensions.overlays.default
    inputs.nixd.overlays.default
  ];
}
