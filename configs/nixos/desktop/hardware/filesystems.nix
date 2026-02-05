{ config, ... }:
let
  rootLabel = "nixos";
  swapLabel = "swap";
  bootLabel = "boot";

  mkFS = label: fsType: { inherit label fsType; };
  btrfsOptions = subvol: extra: { options = [ "subvol=${subvol}" ] ++ extra; };
  defaultBTRFSOptions = [
    "compress-force=zstd:1"
    "noatime"
  ];
  mkBTRFS =
    label: subvol: extra:
    (mkFS label "btrfs") // (btrfsOptions subvol extra);
  mkBoot = label: mkFS label "vfat";
  bootMP = config.boot.loader.efi.efiSysMountPoint;
in
{
  fileSystems = {
    "/" = mkBTRFS rootLabel "@root" defaultBTRFSOptions;
    "/var" = mkBTRFS rootLabel "@var" defaultBTRFSOptions;
    "/tmp" = mkBTRFS rootLabel "@tmp" defaultBTRFSOptions;
    "/nix" = mkBTRFS rootLabel "@nix" defaultBTRFSOptions;
    "/home" = mkBTRFS rootLabel "@home" [
      "compress-force=zstd:1"
      "relatime"
    ];

    ${bootMP} = mkBoot bootLabel; # should be /boot by default
  };

  # Swap
  swapDevices = [ { label = swapLabel; } ];

  # BTRFS Scrub
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };
}
