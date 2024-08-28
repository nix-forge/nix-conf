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

  # Mount a drive to user's home directory for all normal users
  # use custom option that stores all normal users
  users = config.users.normalUsers;
  # map each user to a name value pair for the mount point
  homeMounts =
    name: mount:
    lib.pipe users [
      (builtins.map (user: (lib.attrsets.nameValuePair "${user.home}/${name}" mount)))
      builtins.listToAttrs
    ];

  # Define the games drive mount points
  gamesDrive = homeMounts "games" (mkBTRFS "games" "games");

in
{
  fileSystems = {
    "/" = mkBTRFS rootLabel "@root";
    "/var" = mkBTRFS rootLabel "@var";
    "/tmp" = mkBTRFS rootLabel "@tmp";
    "/nix" = mkBTRFS rootLabel "@nix";
    "/home" = mkBTRFS rootLabel "@home";

    ${bootMP} = mkBoot bootLabel;
  } // gamesDrive;

  # Swap
  swapDevices = [ { label = swapLabel; } ];

  # BTRFS Scrub
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };
}
