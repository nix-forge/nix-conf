{
  config,
  lib,
  pkgs,
  utils,
  ...
}:
let
  cfg = config.hardware.storage.encryptedRoot;
  destinations = cfg.backup.destinations;
  mounts =
    if cfg.enable then
      [
        "/"
        "/srv/data"
      ]
    else
      [
        "/"
        "/mnt/games"
      ];
  units = [
    "smartd.service"
    "fstrim.service"
  ]
  ++ map (path: "btrfs-scrub-${utils.escapeSystemdPath path}.service") mounts
  ++ lib.optionals cfg.enable [ "desktop-data-ready.service" ]
  ++ lib.optionals cfg.enable (
    lib.concatMap
      (name: [
        "desktop-snapshot-${name}-timeline.service"
        "desktop-snapshot-${name}-cleanup.service"
      ])
      [
        "home"
        "data"
        "work"
      ]
  )
  ++ lib.concatMap (name: [
    "restic-backups-desktop-${name}.service"
    "desktop-backup-verify-${name}.service"
    "desktop-backup-cold-${name}.service"
  ]) (builtins.attrNames destinations);
  policy = pkgs.writeText "desktop-storage-health.json" (
    builtins.toJSON {
      inherit mounts units;
      encrypted = cfg.enable;
      warningPercent = 80;
      stateDirectory = "/var/lib/desktop-storage";
      backupPolicy = "/etc/desktop-storage/backup-policy.json";
    }
  );
  helper = pkgs.writeShellApplication {
    name = "desktop-storage-status";
    runtimeInputs = [
      config.system.build.desktopBackupCheck
      pkgs.python3
      pkgs.btrfs-progs
      pkgs.systemd
      pkgs.util-linux
      pkgs.libnotify
    ];
    text = ''
      exec ${lib.getExe pkgs.python3} ${./health.py} ${policy} "$@"
    '';
  };
in
{
  config = {
    environment.systemPackages = [ helper ];
    systemd.tmpfiles.rules = [
      "d /var/lib/desktop-storage 0755 root root - -"
      "d /var/lib/desktop-storage/checks 0755 root root - -"
    ];
    systemd.services.desktop-storage-health = {
      description = "Check storage capacity, Btrfs counters and backup verification";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe helper} refresh";
        UMask = "0022";
        Nice = 15;
        IOSchedulingClass = "idle";
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ReadWritePaths = [ "/var/lib/desktop-storage" ];
        PrivateTmp = true;
      };
    };
    systemd.timers.desktop-storage-health = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5m";
        OnUnitActiveSec = "30m";
      };
    };
    systemd.user.services.desktop-storage-notify = {
      description = "Show changed storage health warnings";
      after = [ "graphical-session.target" ];
      requisite = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe helper} notify";
      };
    };
    systemd.user.timers.desktop-storage-notify = {
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      timerConfig = {
        OnActiveSec = "1m";
        OnUnitActiveSec = "10m";
      };
    };
    # smartd has its own event path; health polling additionally catches daemon
    # failures. This desktop has one trusted interactive account.
    services.smartd.notifications.systembus-notify.enable = true;
    services.systembus-notify.enable = true;
  };
}
