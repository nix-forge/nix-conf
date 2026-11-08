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
