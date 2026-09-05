{ modules, inputs, ... }:
let
  zenNativeBuilderCopyFixOverlay =
    _final: prev:
    let
      incompatibleCopy = "cp -P --no-preserve=mode,ownership --remove-destination";
      compatibleCopy = "cp -P --remove-destination";
    in
    {
      # The Determinate native builder's store mount rejects the permission
      # update made by this GNU cp option combination. The Zen wrapper already
      # runs chmod immediately after the copy, so dropping these options keeps
      # the intended mode while making the wrapper portable across builders.
      wrapFirefox =
        browser: wrapperArgs:
        let
          wrapped = prev.wrapFirefox browser wrapperArgs;
        in
        if prev.lib.hasPrefix "zen-" (browser.pname or "") then
          wrapped.overrideAttrs (old: {
            buildCommand =
              assert prev.lib.assertMsg (prev.lib.hasInfix incompatibleCopy old.buildCommand)
                "Zen wrapper copy workaround no longer matches the upstream build command";
              builtins.replaceStrings [ incompatibleCopy ] [ compatibleCopy ] old.buildCommand;
          })
        else
          wrapped;
    };
in
{
  system = "x86_64-linux";
  hostName = "desktop";

  secrets = {
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFwSeiaY3PpNjPDaFA9bDPeFaLU5HYi0PrJKEEYIt3Vs";
  };

  nixpkgsArgs = {
    overlays = [
      inputs.nixpkgs-personal.overlays.default
      zenNativeBuilderCopyFixOverlay
    ];
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
    virtualisation-libvirt
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
      # OpenSSH evaluates remote commands with the account's login shell, so
      # use Bash here as well as in interactive terminal sessions.
      shell = inputs.nixpkgs.legacyPackages.x86_64-linux.bashInteractive;
    };
  };
}
