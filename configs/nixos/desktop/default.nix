{ modules, ... }:
{
  system = "x86_64-linux";
  hostName = "desktop";
  sshPubKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFwSeiaY3PpNjPDaFA9bDPeFaLU5HYi0PrJKEEYIt3Vs";

  nixpkgsArgs = {
    config = {
      allowUnfree = true;
      allowUnfreePredicate = _: true;
      allowVariants = true;
      allowBroken = false;
      # allowAliases = false;

      cudaSupport = true;
    };
  };

  modules = with modules; [
    base-base
    boot
    agenix

    ./hardware/filesystems.nix
  ];

  # modules =
  #   with (
  #     tree.hosts.${folderName} // tree.hosts.${folderName}.hardware // tree.configs.os
  #   ); [
  #     ## Base
  #     base.nix-settings
  #     ./cache.nix
  #     (import ./secrets.nix { primaryUser = "ianmh"; })
  #     base.base
  #     base.kernel
  #     base.packages
  #     # secrets
  #     users
  #     (
  #       { pkgs, ... }:
  #       {
  #         programs.nix-ld = {
  #           enable = true;
  #           libraries = [
  #             pkgs.libxcrypt
  #             pkgs.libxcrypt-legacy
  #           ];
  #         };
  #       }
  #     )

  #     ## Boot
  #     boot.generic
  #     boot.grub
  #     boot.grub.dual-boot
  #     kernel-modules
  #     # plymouth

  #     ## Locale
  #     { time.timeZone = "America/Los_Angeles"; }
  #     locale.timesync
  #     # keyboard

  #     ## Hardware
  #     filesystems
  #     gpu
  #     cpu
  #     # kernel-patches
  #     power
  #     audio
  #     monitor
  #     keyboard
  #     networking
  #     hardware.zram
  #     hardware.networking
  #     hardware.bluetooth
  #     hardware.tpm
  #     hardware.firmware
  #     hardware.sound
  #     hardware.ssd
  #     hardware.storage
  #     other
  #     gaming

  #     ## Virtualization
  #     virtualisation.docker
  #     virtualisation.libvirt

  #     ## Desktop Environments
  #     # desktop-envs.gnome
  #     # desktop-envs.plasma
  #     desktop-envs.hyprland
  #     # desktop-envs.cosmic
  #     # {
  #     #   environment.pathsToLink = [
  #     #     "/share/applications"
  #     #     "/share/xdg-desktop-portal"
  #     #   ];
  #     # }

  #     ## Display Managers
  #     # display-managers.greetd
  #     display-managers.gdm
  #     # display-managers.sddm

  #     ## Security
  #     security

  #     ## Services
  #     services.disable-hibernate
  #     # services.runners

  #     # Programs
  #     # TODO: add neovim base config and better config in home-manager

  #     ## Theming
  #     stylix.base
  #     stylix.cursor
  #     stylix.fonts
  #     stylix.icons

  #     ## Server
  #     server.ssh
  #   ];
}
