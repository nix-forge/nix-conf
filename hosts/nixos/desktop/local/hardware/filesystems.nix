{
  config,
  lib,
  pkgs,
  utils,
  ...
}:
let
  homelabMountPoint = "/mnt/homelab";
  homelabScrubService = "btrfs-scrub-${utils.escapeSystemdPath homelabMountPoint}";
  homelabKeyFile = config.hardware.storage.encryptedRoot.homelabKeyFile;
  rootScrubPolicy = pkgs.writeText "desktop-root-scrub.json" (
    builtins.toJSON {
      stateDirectory = "/var/lib/desktop-storage";
      bulkLock = "/run/workstation-workloads/bulk.lock";
      swapfile = "/swap/workstation";
      swapUnit = "swap-workstation.swap";
    }
  );
  rootScrubProgram = pkgs.writers.writePython3 "desktop-root-scrub" {
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } ../storage/root_scrub.py;
  rootScrub = pkgs.writeShellApplication {
    name = "desktop-root-scrub";
    runtimeInputs = [
      pkgs.btrfs-progs
      pkgs.util-linux
      config.systemd.package
    ];
    text = ''exec ${rootScrubProgram} ${rootScrubPolicy} "$@"'';
  };
in
{
  options.hardware.storage.homelabHdd.enable =
    lib.mkEnableOption "the separately provisioned encrypted homelab HDD";

  config = {
    assertions = [
      {
        assertion =
          !config.hardware.storage.homelabHdd.enable || config.hardware.storage.encryptedRoot.enable;
        message = "Automatic homelab HDD unlocking requires the encrypted Disko root for its private key.";
      }
    ];

    boot.initrd.supportedFilesystems = [ "btrfs" ];

    environment.etc."crypttab" = lib.mkIf config.hardware.storage.homelabHdd.enable {
      text = lib.mkBefore ''
        homelab /dev/disk/by-partlabel/HOMELAB-CRYPT ${homelabKeyFile} luks,noauto,nofail,headless,x-systemd.device-timeout=10s
      '';
    };

    # An automount is a mount point even while the HDD is locked. Inspect the
    # actual filesystem without accessing the path and triggering an unlock.
    systemd.services.${homelabScrubService} = lib.mkIf config.hardware.storage.homelabHdd.enable {
      description = "Scrub the mounted encrypted homelab HDD";
      serviceConfig = {
        Type = "oneshot";
        IOSchedulingClass = "idle";
        CPUSchedulingPolicy = "idle";
        Nice = 19;
      };
      path = [
        pkgs.btrfs-progs
        pkgs.util-linux
      ];
      script = (import ../../../../../lib/templates/text.nix) ./scripts/filesystems-script.sh {
        inherit homelabMountPoint;
      };
    };
    systemd.timers.${homelabScrubService} = lib.mkIf config.hardware.storage.homelabHdd.enable {
      description = "Monthly encrypted homelab HDD scrub";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "Sun *-*-01..07 03:00:00";
        Persistent = true;
        AccuracySec = "1h";
        RandomizedDelaySec = "2h";
      };
    };

    # One scrub per Btrfs filesystem covers all of its subvolumes.
    services.btrfs.autoScrub = {
      enable = true;
      interval = "Sun *-*-01..07 03:00:00";
      limit = "800M";
      fileSystems = [
        "/"
        "/srv/data"
      ];
    };
    system.build.desktopRootScrub = rootScrub;
    # The existing monthly root timer uses this guarded instance. The data
    # volume retains the upstream template because it has no active swapfile.
    systemd.services."btrfs-scrub@-" = lib.mkIf config.hardware.storage.encryptedRoot.enable {
      description = "Complete root Btrfs scrub with guarded temporary swapfile suspension";
      unitConfig.ConditionPathIsMountPoint = "/";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe rootScrub} run";
        ExecStopPost = "${lib.getExe rootScrub} recover";
        TimeoutStartSec = "3h";
        TimeoutStopSec = "5min";
        KillMode = "mixed";
        MemoryMax = "512M";
        UMask = "0077";
        Nice = 19;
        IOSchedulingClass = "idle";
      };
    };

    # Batch TRIM avoids continuous discards during large Nix store collections.
    systemd.services.fstrim.unitConfig.ConditionACPower = true;

    # An absent volume must not cause a scrub of its parent filesystem.
    systemd.services."btrfs-scrub@".unitConfig.ConditionPathIsMountPoint = "%f";
    systemd.timers."btrfs-scrub@".timerConfig = {
      AccuracySec = lib.mkForce "1h";
      RandomizedDelaySec = "2h";
    };
  };
}
