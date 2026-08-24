{ config, ... }:
let
  rootLabel = "nixos";
  swapLabel = "swap";
  bootLabel = "boot";
  gamesDevice = "/dev/disk/by-uuid/f4595c1c-d701-45f2-b04a-d33e7ea0e8f6";
  gamesMountPoint = "/home/ianmh/games";

  mkFS = label: fsType: { inherit label fsType; };
  btrfsOptions = subvol: extra: { options = [ "subvol=${subvol}" ] ++ extra; };
  defaultBTRFSOptions = [
    # `compress` applies Btrfs' incompressibility heuristic.  Unlike
    # `compress-force`, it avoids spending CPU trying to compress game assets,
    # package archives, and other already-compressed data.
    "compress=zstd:1"
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
    "/home" = mkBTRFS rootLabel "@home" defaultBTRFSOptions;

    # Dedicated NVMe Steam library, shared with Windows through WinBtrfs.
    # The Btrfs default subvolume contains a `games` subvolume.  Mount that
    # subvolume directly so Steam's persisted library path
    # (/home/ianmh/games/SteamLibrary) resolves to the shared library on both
    # operating systems.
    # The non-critical game disk must not block the desktop from booting if it
    # is absent or unhealthy.
    ${gamesMountPoint} = {
      device = gamesDevice;
      fsType = "btrfs";
      options = [
        "subvol=games"
        "compress=zstd:1"
        "noatime"
        "discard=async"
        "nofail"
        "x-systemd.device-timeout=10s"
      ];
    };

    ${bootMP} = mkBoot bootLabel; # should be /boot by default
  };

  # Swap
  swapDevices = [ { label = swapLabel; } ];

  # BTRFS Scrub
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    # A scrub covers all subvolumes on its Btrfs filesystem, so one root entry
    # is sufficient for the system drive.  The independent games volume needs
    # its own entry.
    fileSystems = [
      "/"
      gamesMountPoint
    ];
  };
}
