{
  config,
  lib,
  utils,
  ...
}:
let
  rootLabel = "nixos";
  swapLabel = "swap";
  bootLabel = "boot";
  gamesDevice = "/dev/disk/by-uuid/f4595c1c-d701-45f2-b04a-d33e7ea0e8f6";
  # The shared Steam library is system storage, not a user's home data. Keep
  # it at a neutral mount point so any user or launcher can opt into it without
  # hard-coding a particular account's home directory.
  gamesMountPoint = "/mnt/games";
  gamesGroup = "users";
  gamesScrubTimer = "btrfs-scrub-${utils.escapeSystemdPath gamesMountPoint}";

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
  mkBoot =
    label:
    (mkFS label "vfat")
    // {
      # The ESP is FAT and therefore has no per-file Unix ownership.  Mount it
      # root-only while Linux is running so systemd-boot's random seed cannot
      # be read by unprivileged local users.  UEFI firmware ignores these
      # Linux-only masks when it reads boot files before the kernel starts.
      options = [
        "fmask=0077"
        "dmask=0077"
      ];
    };
  bootMP = config.boot.loader.efi.efiSysMountPoint;
in
{
  # NixOS's built-in `users` group covers normal local accounts without tying
  # this shared game library to a particular login.  The Btrfs subvolume is
  # also used from Windows, so make its Steam content directory group-writable
  # when the volume is available.
  systemd.tmpfiles.rules = [
    "d ${gamesMountPoint} 2775 root ${gamesGroup} - -"
    "d ${gamesMountPoint}/steamapps 2775 root ${gamesGroup} - -"
  ];

  # Only the filesystem needed to mount this desktop's root belongs in the
  # initrd.  Removable-media support is available after the real system starts.
  boot.initrd.supportedFilesystems = [ "btrfs" ];

  fileSystems = {
    "/" = mkBTRFS rootLabel "@root" defaultBTRFSOptions;
    "/var" = mkBTRFS rootLabel "@var" defaultBTRFSOptions;
    "/tmp" = mkBTRFS rootLabel "@tmp" defaultBTRFSOptions;
    "/nix" = mkBTRFS rootLabel "@nix" defaultBTRFSOptions;
    "/home" = mkBTRFS rootLabel "@home" defaultBTRFSOptions;

    # Dedicated NVMe Steam library, shared with Windows through WinBtrfs.
    # The Btrfs default subvolume contains a `games` subvolume. Mount it at a
    # neutral system location so Steam libraries can be selected by any user.
    # The non-critical game disk must not block the desktop from booting if it
    # is absent or unhealthy.
    ${gamesMountPoint} = {
      device = gamesDevice;
      fsType = "btrfs";
      options = [
        "subvol=games"
        "compress=zstd:1"
        "noatime"
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
    # First Sunday of every month, outside the normal desktop-use window.
    # Btrfs recommends monthly scrub; the limit protects interactivity because
    # this desktop uses the NVMe `none` I/O scheduler, where idle I/O priority
    # alone is not a reliable throttle.
    interval = "Sun *-*-01..07 03:00:00";
    limit = "800M";
    # A scrub covers all subvolumes on its Btrfs filesystem, so one root entry
    # is sufficient for the system drive.  The independent games volume needs
    # its own entry.
    fileSystems = [
      "/"
      gamesMountPoint
    ];
  };

  # The system is a mains-powered desktop, so defer periodic trim until AC is
  # available.  Btrfs enables asynchronous discard itself on supported modern
  # devices; do not pin that implementation detail in fstab.  The periodic
  # batch trim remains the explicit maintenance policy for this host.
  systemd.services.fstrim.unitConfig.ConditionACPower = true;

  # NixOS's auto-scrub timer intentionally uses a one-day accuracy window.
  # This single desktop can use a narrower, jittered early-morning window while
  # retaining persistence across downtime.
  systemd.timers = {
    "btrfs-scrub--".timerConfig = {
      AccuracySec = lib.mkForce "1h";
      RandomizedDelaySec = "2h";
    };
    ${gamesScrubTimer}.timerConfig = {
      AccuracySec = lib.mkForce "1h";
      RandomizedDelaySec = "2h";
    };
  };
}
