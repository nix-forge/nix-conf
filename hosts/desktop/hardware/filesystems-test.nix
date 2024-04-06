{ config, lib, ... }:
let
  rootLabel = "nixos";
  swapLabel = "swap";
  bootLabel = "boot";
in
{
  fileSystems =
    let
      mkFS = label: fsType: { inherit label fsType; };
      mkBTRFS =
        label: subvol:
        (mkFS label "btrfs")
        // {
          options = [
            "subvol=${subvol}"
            "compress-force=ztsd:1"
            "noatime"
          ];
        };
      mkBoot = label: mkFS label "vfat";
      bootMP = config.boot.loader.efi.efiSysMountPoint;
    in
    {
      "/" = mkBTRFS rootLabel "@root";
      "/home" = mkBTRFS rootLabel "@home";
      "/nix" = mkBTRFS rootLabel "@nix";
      "/var" = mkBTRFS rootLabel "@var";
      "/tmp" = mkBTRFS rootLabel "@tmp";

      ${bootMP} = mkBoot bootLabel;
    };

  # Swap
  swapDevices = [ { label = swapLabel; } ];
  boot.resumeDevice = "/dev/disk/by-label/${swapLabel}";

  # Btrfs
  services.btrfs.autoScrub = {
    enable = true;
    fileSystems = [ "/" ];
    interval = "monthly";
  };

  # Enable SSD TRIM support
  services.fstrim.enable = lib.mkDefault true;

  # Allow Nix to automatically optimise the store
  nix.settings.auto-optimise-store = true;
}
