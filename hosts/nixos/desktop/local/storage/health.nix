{
  config,
  lib,
  myLib,
  pkgs,
  utils,
  ...
}:
let
  writeShellApplication = myLib.writers.writeShellApplication { inherit pkgs; };
  cfg = config.hardware.storage.encryptedRoot;
  inherit (import ./.storage-roles.nix) dataMount gamesMount homelabMount;
  destinations = cfg.backup.destinations;
  inherit (cfg) health;
  primaryMounts =
    if cfg.enable then
      [
        "/"
        dataMount
      ]
    else
      [
        "/"
        gamesMount
      ];
  mounts =
    primaryMounts ++ lib.optional (config.hardware.storage.homelabHdd.enable or false) homelabMount;
  units = [
    "smartd.service"
    "fstrim.service"
  ]
  ++ lib.optionals cfg.capacity.enable [
    "desktop-storage-collect.service"
    "desktop-generation-retention.service"
  ]
  ++ map (path: "btrfs-scrub@${utils.escapeSystemdPath path}.service") primaryMounts
  ++ lib.optional (config.hardware.storage.homelabHdd.enable or false
  ) "btrfs-scrub-${utils.escapeSystemdPath homelabMount}.service"
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
  ]) (builtins.attrNames destinations)
  ++ lib.optional (config.systemd.services.restic-backups-desktop-homelab-databases.enable or false
  ) "restic-backups-desktop-homelab-databases.service";
  policy = pkgs.writeText "desktop-storage-health.json" (
    builtins.toJSON {
      inherit mounts units;
      inherit (health) probes notificationCommand;
      encrypted = cfg.enable;
      warningPercent = 80;
      capacityCommand = lib.optionals cfg.capacity.enable [
        (lib.getExe config.system.build.desktopStorageCapacity)
        "status"
      ];
      stateDirectory = "/var/lib/desktop-storage";
      backupPolicy = "/etc/desktop-storage/backup-policy.json";
    }
  );
  helper = writeShellApplication {
    name = "desktop-storage-status";
    runtimeInputs = [
      config.system.build.desktopBackupCheck
      pkgs.btrfs-progs
      pkgs.systemd
      pkgs.util-linux
      pkgs.libnotify
    ];
    text =
      myLib.templates.renderText
        {
          name = "desktop-storage-status.sh";
          text = ''
            # shellcheck shell=bash
            exec @health@ @policy@ "$@"
          '';
        }
        {
          health =
            lib.getExe'
              (import ../../../../../flake/runtime-packages.nix { inherit pkgs; }).desktopStorageRuntime
              "desktop-storage-health";
          inherit policy;
        };
  };
in
{
  options.hardware.storage.encryptedRoot.health = {
    notificationCommand = lib.mkOption {
      type = lib.types.nullOr (lib.types.listOf lib.types.str);
      default = null;
      description = "Optional session-independent delivery command. Receives redacted event JSON on stdin and must return success only after accepting delivery. Credentials belong in runtime files; null retains pending warnings locally.";
    };
    probes = lib.mkOption {
      default = { };
      description = "Additional bounded health commands and successful-work freshness checks. Probe names are public notification labels.";
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            command = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Command arguments with an absolute executable; nonzero exit is an alert. Output is never included in notifications.";
            };
            timeoutSeconds = lib.mkOption {
              type = lib.types.ints.positive;
              default = 15;
              description = "Maximum command duration.";
            };
            receipt = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Runtime JSON containing completed Unix seconds and optional result, which must be success. Missing, malformed and future records alert.";
            };
            maxAgeSeconds = lib.mkOption {
              type = lib.types.ints.positive;
              default = 86400;
              description = "Maximum age of successful work.";
            };
          };
        }
      );
    };
  };
  config = {
    assertions = [
      {
        assertion =
          health.notificationCommand == null
          || (
            health.notificationCommand != [ ] && lib.hasPrefix "/" (builtins.head health.notificationCommand)
          );
        message = "Storage health notificationCommand must have an absolute executable.";
      }
    ]
    ++ lib.mapAttrsToList (_: probe: {
      assertion =
        (probe.command != [ ] || probe.receipt != null)
        && (probe.command == [ ] || lib.hasPrefix "/" (builtins.head probe.command));
      message = "Storage health probes require a command or receipt, and command executables must be absolute.";
    }) health.probes;
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
    # This timer is independent of collection and the graphical session, so a
    # failed collector can still deliver its stale-result alert.
    systemd.services.desktop-storage-delivery = {
      description = "Deliver changed workstation health state or retain pending warnings";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe helper} deliver";
        UMask = "0077";
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ReadWritePaths = [ "/var/lib/desktop-storage" ];
        PrivateTmp = true;
      };
    };
    systemd.timers.desktop-storage-delivery = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "6m";
        OnUnitActiveSec = "10m";
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
