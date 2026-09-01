{
  config,
  lib,
  utils,
  ...
}:
let
  encryptedRoot = config.hardware.storage.encryptedRoot.enable;
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
    # Btrfs otherwise defaults to asynchronous discard on supported devices.
    # Determinate Nixd can delete many store paths at once, so batch TRIM is
    # preferable to issuing discards while its collector is active.
    "nodiscard"
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
  # This switch exists only during this desktop's one-time Disko migration.
  # It is deliberately declared locally: a shared storage module must not
  # expose a host-specific root-layout transition as a reusable option.
  options.hardware.storage.encryptedRoot.enable = lib.mkEnableOption ''
    this desktop's Disko-managed LUKS2 encrypted root layout
  '';

  config = lib.mkMerge [
    {
      # NixOS's built-in `users` group covers normal local accounts without
      # tying this shared game library to a particular login.  The Btrfs
      # subvolume is also used from Windows, so make its Steam content
      # directory group-writable when the volume is available.
      systemd.tmpfiles.rules = [
        "d ${gamesMountPoint} 2775 root ${gamesGroup} - -"
        "d ${gamesMountPoint}/steamapps 2775 root ${gamesGroup} - -"
      ];

      # Only the filesystem needed to mount this desktop's root belongs in the
      # initrd. Removable-media support is available after the real system
      # starts.
      boot.initrd.supportedFilesystems = [ "btrfs" ];

      fileSystems.${gamesMountPoint} = {
        # Dedicated NVMe Steam library, shared with Windows through WinBtrfs.
        # Its absence must not block the desktop from booting.
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

      # Btrfs scrub covers all subvolumes on a filesystem, so one root entry
      # is enough for either storage layout. The games drive is independent.
      services.btrfs.autoScrub = {
        enable = true;
        interval = "Sun *-*-01..07 03:00:00";
        limit = "800M";
        fileSystems = [
          "/"
          gamesMountPoint
        ];
      };

      # Keep continuous discard off for the Btrfs filesystem that contains
      # `/nix`; the shared SSD module runs periodic batch TRIM instead.
      systemd.services.fstrim.unitConfig.ConditionACPower = true;

      # NixOS's auto-scrub timer intentionally uses a one-day accuracy window.
      # This single desktop uses a narrower, jittered early-morning window.
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

    # Disko creates its own Btrfs subvolumes, initrd LUKS mapping, and
    # encrypted swap. Keep the currently-deployed plaintext root layout behind
    # an explicit switch so the offline migration does not merge incompatible
    # mounts or leave a plaintext swap device behind. This defaults to false
    # and changes nothing on the current live desktop.
    (lib.mkIf (!encryptedRoot) {
      fileSystems = {
        "/" = mkBTRFS rootLabel "@root" defaultBTRFSOptions;
        "/var" = mkBTRFS rootLabel "@var" defaultBTRFSOptions;
        "/tmp" = mkBTRFS rootLabel "@tmp" defaultBTRFSOptions;
        "/nix" = mkBTRFS rootLabel "@nix" defaultBTRFSOptions;
        "/home" = mkBTRFS rootLabel "@home" defaultBTRFSOptions;
        ${bootMP} = mkBoot bootLabel; # should be /boot by default
      };

      # Legacy plaintext swap. Disko replaces this with a LUKS-encrypted Btrfs
      # swapfile, retaining the same zram-first priority order.
      swapDevices = [ { label = swapLabel; } ];
    })
  ];
}
