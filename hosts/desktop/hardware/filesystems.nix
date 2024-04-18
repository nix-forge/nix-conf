{ config, lib, ... }:
let
  rootLabel = "nixos";
  swapLabel = "swap";
  bootLabel = "boot";

  mkFS = label: fsType: { inherit label fsType; };
  btrfsOptions = subvol: {
    options = [
      "subvol=${subvol}"
      "compress-force=zstd:1"
      "noatime"
    ];
  };
  mkBTRFS = label: subvol: (mkFS label "btrfs") // btrfsOptions subvol;
  mkBoot = label: mkFS label "vfat";
  bootMP = config.boot.loader.efi.efiSysMountPoint;
in
{
  fileSystems = {
    "/" = mkBTRFS rootLabel "@root";
    "/var" = mkBTRFS rootLabel "@var";
    "/tmp" = mkBTRFS rootLabel "@tmp";
    "/nix" = mkBTRFS rootLabel "@nix";
    "/home" = mkBTRFS rootLabel "@home";

    ${bootMP} = mkBoot bootLabel;
  };

  # Swap
  swapDevices = [ { label = swapLabel; } ];
  boot.resumeDevice = "/dev/disk/by-label/${swapLabel}";

  # BTRFS Scrub
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };

  # Enable SSD TRIM support
  services.fstrim.enable = lib.mkDefault true;

  # Allow Nix to automatically optimise the store
  nix.settings.auto-optimise-store = true;
}
