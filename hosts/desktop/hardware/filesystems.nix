{ config, lib, ... }:
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
  gamesDrive = homeMounts "games" (mkBTRFS "games" "games" defaultBTRFSOptions);

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
  }
  // gamesDrive;

  # Swap
  swapDevices = [ { label = swapLabel; } ];

  # BTRFS Scrub
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };
}
