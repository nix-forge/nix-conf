{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.storage.encryptedRoot;
  directory = "/var/lib/desktop-storage/database-backups";
  sqlite =
    unit: name: path:
    lib.optional (config.systemd.services.${unit}.enable or false) { inherit name path; };
  optionalSqlite =
    unit: name: path:
    map (entry: entry // { optional = true; }) (sqlite unit name path);
  cluster = name: user: socket: package: {
    inherit
      name
      user
      socket
      package
      ;
    commandPrefix = [
      (lib.getExe' pkgs.util-linux "runuser")
      "-u"
      user
      "--"
    ];
  };
  policy = pkgs.writeText "homelab-database-backup.json" (
    builtins.toJSON {
      inherit directory;
      sqlite = lib.concatLists [
        (sqlite "aurral" "aurral" "/var/lib/aurral/aurral.db")
        (sqlite "navidrome" "navidrome"
          "${config.services.navidrome.settings.DataFolder or "/var/lib/navidrome"}/navidrome.db"
        )
        (optionalSqlite "navidrome" "navidrome-lyrics"
          "${
            config.services.navidrome.settings.DataFolder or "/var/lib/navidrome"
          }/plugins/nd-lyrics/kvstore.db"
        )
        (optionalSqlite "navidrome" "navidrome-playlists"
          "${
            config.services.navidrome.settings.DataFolder or "/var/lib/navidrome"
          }/plugins/listenbrainz-daily-playlist/taskqueue.db"
        )
        (sqlite "audiobookshelf" "audiobookshelf"
          "/var/lib/${config.services.audiobookshelf.dataDir}/config/absdatabase.sqlite"
        )
        (sqlite "komga" "komga" "${config.services.komga.stateDir}/database.sqlite")
        (optionalSqlite "komga" "komga-tasks" "${config.services.komga.stateDir}/tasks.sqlite")
        (sqlite "jellyfin" "jellyfin" "${config.services.jellyfin.dataDir}/data/jellyfin.db")
        (optionalSqlite "jellyfin" "intro-skipper"
          "${config.services.jellyfin.dataDir}/data/introskipper/introskipper-v2.db"
        )
        (sqlite "prowlarr" "prowlarr" "${config.services.prowlarr.dataDir}/prowlarr.db")
        (sqlite "lidarr" "lidarr" "${config.services.lidarr.dataDir}/lidarr.db")
        (sqlite "radarr" "radarr" "${config.services.radarr.dataDir}/radarr.db")
        (sqlite "sonarr" "sonarr" "${config.services.sonarr.dataDir}/sonarr.db")
        (sqlite "bazarr" "bazarr" "${config.services.bazarr.dataDir}/db/bazarr.db")
        (sqlite "seerr" "seerr" "${config.services.seerr.configDir}/db/db.sqlite3")
      ];
      postgresql =
        lib.optional config.services.postgresql.enable (
          cluster "postgresql" "postgres" "/run/postgresql" config.services.postgresql.package
        )
        ++ lib.optional (config.homelab.apps.bookorbit.enable && config.homelab.apps.bookorbit.native) (
          cluster "bookorbit" "bookorbit" "/run/bookorbit-postgres" pkgs.postgresql_18
        );
    }
  );
  exporter = pkgs.writers.writePython3 "export-homelab-databases" {
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } (builtins.readFile ./scripts/export_homelab_databases.py);
  mainJob = config.services.restic.backups.desktop-homelab;
  mainService = config.systemd.services.restic-backups-desktop-homelab.serviceConfig;
in
{
  config = lib.mkIf (cfg.enable && config.hardware.storage.homelabHdd.enable) {
    hardware.storage.encryptedRoot.backup = {
      coldPaths = lib.mkAfter [ directory ];
      coldPrepareCommand = [
        (toString exporter)
        (toString policy)
      ];
    };
    # The daily set contains complete logical exports only. The weekly job
    # excludes this staging tree, including any interrupted pending generation.
    services.restic.backups.desktop-homelab-databases = {
      inherit (mainJob)
        package
        repositoryFile
        passwordFile
        environmentFile
        ;
      initialize = false;
      createWrapper = true;
      inhibitsSleep = true;
      paths = [ directory ];
      exclude = [
        "${directory}/pending-*"
        "${directory}/.latest-*"
      ];
      pruneOpts = [ ];
      extraBackupArgs = [
        "--tag desktop-databases"
        "--json"
      ];
      backupPrepareCommand = ''
        ${lib.getExe pkgs.python3} ${./backup_helper.py} ${
          config.environment.etc."desktop-storage/backup-policy.json".source
        } guard homelab
        ${lib.getExe' pkgs.util-linux "flock"} --exclusive /run/workstation-workloads/bulk.lock ${exporter} ${policy}
      '';
      timerConfig = {
        OnCalendar = "*-*-* 05:00:00";
        Persistent = true;
        RandomizedDelaySec = "15m";
      };
    };
    systemd.services.restic-backups-desktop-homelab-databases = {
      path = [
        pkgs.util-linux
        config.programs.ssh.package
      ];
      requires = [
        "nix-seal-activate.service"
      ]
      ++ lib.optional cfg.capacity.enable "desktop-storage-cache-ready.service";
      after = [
        "nix-seal-activate.service"
      ]
      ++ lib.optional cfg.capacity.enable "desktop-storage-cache-ready.service";
      unitConfig.RequiresMountsFor = [
        "/var/lib/desktop-storage"
      ]
      ++ cfg.backup.destinations.homelab.requiredMounts;
      environment = {
        GOMEMLIMIT = "8GiB";
      }
      // lib.optionalAttrs cfg.capacity.enable {
        RESTIC_CACHE_DIR = lib.mkForce "/srv/data/cache/restic/homelab";
        TMPDIR = "/srv/data/cache/restic/tmp";
      };
      serviceConfig = {
        inherit (mainService)
          MemoryAccounting
          MemoryHigh
          MemoryMax
          MemorySwapMax
          OOMPolicy
          CPUWeight
          IOWeight
          KillSignal
          KillMode
          TimeoutStopSec
          ;
        ExecStartPost = [
          "${lib.getExe pkgs.python3} ${./backup_helper.py} ${
            config.environment.etc."desktop-storage/backup-policy.json".source
          } stamp homelab database-backup"
        ];
        ExecStopPost = [
          "${lib.getExe pkgs.python3} ${./backup_helper.py} ${
            config.environment.etc."desktop-storage/backup-policy.json".source
          } finish homelab database-backup"
        ];
        UMask = "0077";
        Nice = 15;
        IOSchedulingClass = "idle";
        TimeoutStartSec = "2h";
      };
    };
    hardware.storage.encryptedRoot.health.probes.homelab-databases = {
      receipt = "/var/lib/desktop-storage/checks/homelab-database-backup.json";
      maxAgeSeconds = 172800;
    };
    system.build.homelabDatabaseBackup = { inherit exporter policy; };
  };
}
