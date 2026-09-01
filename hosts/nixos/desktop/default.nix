{ modules, inputs, ... }: {
  system = "x86_64-linux";
  hostName = "desktop";

  secrets = {
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFwSeiaY3PpNjPDaFA9bDPeFaLU5HYi0PrJKEEYIt3Vs";
  };

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
    ## Base system
    base-kernel
    base-wordlist
    determinate
    nixSeal
    nix-settings
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
    hardware-storage
    hardware-tpm
    hardware-zram
    gaming

    ## Desktop and services
    # Apply the same Stylix roles before login as the Home Manager desktop.
    # This covers system GTK/Qt programs and provides the primary Fontconfig
    # aliases for every account on the machine.
    stylix
    ../../../modules/nixos/desktop-envs/hyprland.nix
    ../../../modules/nixos/desktop-envs/interactive.nix
    ../../../modules/nixos/display-managers/greetd.nix
    locale-timesync
    ssh
    virtualisation-docker
    # Host-specific sealed system secrets must be imported explicitly: the
    # framework only auto-loads files under local/.
    ./nix-seal.nix
  ];

  homes.ianmh = {
    # Keep desktop-bootstrap available as a standalone recovery profile, but
    # use the complete desktop environment for the installed workstation.
    config = "ianmh@desktop";
    user = {
      description = "Ian Holloway";
      shell = inputs.nixpkgs.legacyPackages.x86_64-linux.nushell;
    };
  };
}
