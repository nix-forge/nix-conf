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
  modules =
    with (tree.hosts.${hostname} // tree.hosts.${hostname}.hardware // tree.hosts.shared);
    [
      ## Base
      base.nix-settings
      base.nix-registry
      base.base
      base.kernel
      base.packages
      users

      ## Boot
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
      hardware.zram
      hardware.networking
      # virtualization
      hardware.bluetooth
      # firmware
      hardware.pipewire
      peripherals.mouse
      gaming.default

      ## Desktop Environments

      # desktop-envs.gnome
      # desktop-envs.plasma
      desktop-envs.hyprland
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

      # Other
      # swaylock setup (replace with hyprlock)
      # keyring
      # polkit

    ]
    ++ [
      ## Environment Variables
      { environment.sessionVariables = lib.cust.env.wayland.all; }
    ];

  overlays = [
    inputs.nur.overlay
    inputs.vscode-extensions.overlays.default
    inputs.nixd.overlays.default
  ];

}
