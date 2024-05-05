{
  config,
  lib,
  ...
}: let
  rootLabel = "nixos";
  swapLabel = "swap";
  bootLabel = "boot";

  mkFS = label: fsType: {inherit label fsType;};
  mkEXT4 = label: mkFS label "ext4";
  mkBoot = label: mkFS label "vfat";
  bootMP = config.boot.loader.efi.efiSysMountPoint;
in {
  fileSystems = {
    "/" = mkEXT4 rootLabel;
    ${bootMP} = mkBoot bootLabel;
  };

  # Swap
  swapDevices = [{label = swapLabel;}];
  boot.resumeDevice = "/dev/disk/by-label/${swapLabel}";

  # Enable SSD TRIM support
  services.fstrim.enable = lib.mkDefault true;

  # Allow Nix to automatically optimise the store
  nix.settings.auto-optimise-store = true;
}
