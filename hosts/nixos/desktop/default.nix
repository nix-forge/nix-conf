{
  lib,
  modules,
  inputs,
  ...
}:
{
  system = "x86_64-linux";
  hostName = "desktop";

  secrets = {
    publicKey = lib.removeSuffix "\n" (builtins.readFile ./local/nix-seal/identity.pub);
  };

  nixpkgsArgs = (import ./local/package-policy.nix { }).lib.targetPackagePolicy inputs;

  modules = with modules; [
    ## Base system
    base-kernel
    base-wordlist
    determinate
    nixSeal
    nix-settings
    codex-runtime
    cache
    registry
    chromium-policies
    security-apparmor
    security-clamav
    security-dbus-dconf
    security-keyring
    security-kernel
    security-pam
    security-pki
    security-polkit
    security-sudo
    security-usbguard
    security-virtualization

    ## Boot and hardware
    boot-generic
    boot-console
    boot-secure-boot
    boot-systemd
    hardware-bluetooth
    hardware-firmware
    hardware-graphics
    hardware-networking
    network-manager
    network-wireless
    network-performance
    network-resolved
    network-unbound
    network-wireguard
    network-blocking
    network-fail2ban
    network-tarpit
    hardware-sound
    hardware-ssd
    hardware-iocost
    system-activation-safety
    network-iwd-profiles
    hardware-storage
    hardware-tpm
    hardware-zram
    yubikey
    gaming

    ## Desktop and services
    # Apply the same Stylix roles before login as the Home Manager desktop.
    # This covers system GTK/Qt programs and provides the primary Fontconfig
    # aliases for every account on the machine.
    stylix
    fonts
    desktop-envs-hyprland
    desktop-envs-interactive
    display-managers-noctalia
    locale-timesync
    services-runners
    services-application-recovery
    ssh
    virtualisation-libvirt

  ];

  homes.ianmh = {
    # Attach the complete home profile to the installed workstation.
    config = "ianmh@desktop";
    user = {
      description = "IanHollow";
      # OpenSSH evaluates remote commands with the account's login shell, so
      # use Bash here as well as in interactive terminal sessions.
      shell = inputs.nixpkgs.legacyPackages.x86_64-linux.bashInteractive;
    };
  };
}
