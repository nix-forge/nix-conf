{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.storage.encryptedRoot;
  destinations = cfg.backup.destinations;
  defaultExcludes = [
    "**/.snapshots"
    "/srv/data/cache"
    "/srv/data/work/scratch"
    "/home/*/.cache"
    "/home/*/.local/share/docker"
    "/var/lib/docker"
    "/var/lib/containerd"
    "/var/lib/libvirt"
    "/var/lib/desktop-storage/restore-tests"
    "/var/lib/systemd/coredump"
  ];
  # Share the bulk lane with user builds; this root-owned lock is provisioned
  # by the desktop memory policy. The per-repository Restic lock is separate.
  bulkLock = "/run/workstation-workloads/bulk.lock";
  # The repository index remains resident even when source trees are excluded.
  # Share the bulk lane's ceiling and leave kernel/cache headroom above the Go
  # soft limit. The 8 GiB pressure threshold caused index/traversal reclaim
  # stalls; keep a 1 GiB margin below the unchanged 10 GiB hard ceiling.
  memoryBudget = {
    MemoryAccounting = true;
    MemoryHigh = "9G";
    MemoryMax = "10G";
    MemorySwapMax = "1G";
    OOMPolicy = "kill";
    CPUWeight = 25;
    IOWeight = 25;
    # Restic flushes its current index when interrupted. Give it time to exit
    # before systemd enforces the cgroup cleanup boundary.
    KillSignal = "SIGINT";
    KillMode = "control-group";
    TimeoutStopSec = "5min";
  };
  # Backups and verification can overlap with exclusive repository maintenance.
  # Let Restic wait for the lock instead of recording a spurious failed attempt.
  guardedRestic = pkgs.writeShellApplication {
    name = "restic-data-cache";
    text =
      lib.optionalString cfg.capacity.enable ''
        ${lib.getExe config.system.build.desktopStorageCapacity} cache >/dev/null
      ''
      + ''
        exec ${lib.getExe pkgs.restic} "$@"
      '';
  };
  restic = pkgs.writeShellApplication {
    name = "restic";
    text = (import ../../../../../lib/templates/text.nix) ./scripts/restic-lock-wait.sh {
      restic = lib.getExe guardedRestic;
      flock = lib.getExe' pkgs.util-linux "flock";
      inherit bulkLock;
    };
  };
  credentialPath = lib.types.strMatching "/[^\n\r ]+";
  python = lib.getExe pkgs.python3;
  helper = ./backup_helper.py;
  helperConfig = pkgs.writeText "desktop-backup-policy.json" (
    builtins.toJSON {
      stateDirectory = "/var/lib/desktop-storage";
      coldPaths = cfg.backup.coldPaths;
      coldUnits = cfg.backup.coldUnits;
      coldUnmounts = cfg.backup.coldUnmounts;
      coldPrepareCommand = cfg.backup.coldPrepareCommand;
      coldRestic = lib.getExe guardedRestic;
      coldRestoreScratch = if cfg.capacity.enable then "/srv/data/cache/restic/tmp" else null;
      inherit destinations;
    }
  );
  checkPackage = pkgs.writeShellApplication {
    name = "desktop-backup-check";
    runtimeInputs = [
      pkgs.python3
      restic
      pkgs.coreutils
      pkgs.util-linux
      config.programs.ssh.package
      pkgs.procps
      config.systemd.package
    ];
    text = (import ../../../../../lib/templates/text.nix) ./scripts/desktop-backup-check.sh {
      inherit python;
      inherit helper;
      inherit helperConfig;
    };
  };
  guard = name: "${python} ${helper} ${helperConfig} guard ${lib.escapeShellArg name}";
  stamp =
    name: phase: "${python} ${helper} ${helperConfig} stamp ${lib.escapeShellArg name} ${phase}";
  finish =
    name: operation:
    "${python} ${helper} ${helperConfig} finish ${lib.escapeShellArg name} ${operation}";
  jobName = name: "desktop-${name}";
  resticJob = name: destination: {
    package = restic;
    inherit (destination) repositoryFile passwordFile environmentFile;
    initialize = false;
    createWrapper = true;
    inhibitsSleep = true;
    paths = cfg.backup.paths;
    exclude = cfg.backup.exclude;
    # An independent administrator owns pruning for immutable/append-only
    # destinations. A scheduled workstation backup never deletes old copies.
    pruneOpts = [ ];
    extraBackupArgs = [
      "--tag desktop-files"
      "--exclude-caches"
      "--json"
    ];
    backupPrepareCommand =
      (import ../../../../../lib/templates/text.nix) ./scripts/desktop-backup-check-body.sh.in
        {
          pkgs_runtimeShell = pkgs.runtimeShell;
          guard_name = guard name;
          pkgs_util_linux = pkgs.util-linux;
          inherit python;
          inherit helper;
          inherit helperConfig;
        };
    timerConfig = {
      OnCalendar = destination.schedule;
      Persistent = true;
      RandomizedDelaySec = "30m";
    };
  };
  verifyJob = name: destination: {
    description = "Read and restore-test desktop backup ${name}";
    wants = [ "network-online.target" ];
    requires = lib.optional cfg.capacity.enable "desktop-storage-cache-ready.service";
    after = [
      "network-online.target"
    ]
    ++ lib.optional cfg.capacity.enable "desktop-storage-cache-ready.service";
    path = [
      restic
      pkgs.coreutils
      pkgs.util-linux
      config.programs.ssh.package
    ];
    environment = removeAttrs config.systemd.services."restic-backups-${jobName name}".environment [
      "PATH"
    ];
    unitConfig.RequiresMountsFor =
      destination.requiredMounts ++ lib.optional cfg.capacity.enable "/srv/data";
    serviceConfig =
      memoryBudget
      // {
        Type = "oneshot";
        User = "root";
        UMask = "0077";
        PrivateTmp = true;
        CacheDirectory = "desktop-backup-verify-${name}";
        CacheDirectoryMode = "0700";
        Nice = 15;
        IOSchedulingClass = "idle";
        ExecStopPost = [ (finish name "verification") ];
      }
      // lib.optionalAttrs (destination.environmentFile != null) {
        EnvironmentFile = destination.environmentFile;
      };
    script = (import ../../../../../lib/templates/text.nix) ./scripts/backups-script.sh {
      guard_name = guard name;
      stamp_name_integrity = stamp name "integrity";
      inherit python;
      inherit helper;
      inherit helperConfig;
      lib_escapeShellArg_name = lib.escapeShellArg name;
      stamp_name_restore = stamp name "restore";
    };
  };
  coldJob = name: destination: {
    requires = lib.optional cfg.capacity.enable "desktop-storage-cache-ready.service";
    after = lib.optional cfg.capacity.enable "desktop-storage-cache-ready.service";
    unitConfig.RequiresMountsFor =
      destination.requiredMounts ++ lib.optional cfg.capacity.enable "/srv/data";
    description = "Consistent application backup and verified restore to ${name}";
    # Native applications declare their complete guarded writer set. With no
    # such declaration, the legacy VM/container path still requires rescue mode.
    path = [
      restic
      pkgs.coreutils
      pkgs.util-linux
      pkgs.procps
      config.systemd.package
      config.programs.ssh.package
    ];
    environment =
      removeAttrs config.systemd.services."restic-backups-${jobName name}".environment [ "PATH" ]
      // {
        GOMEMLIMIT = "6GiB";
        RESTIC_PROGRESS_FPS = "0.016666";
      };
    serviceConfig =
      memoryBudget
      // {
        Type = "oneshot";
        User = "root";
        UMask = "0077";
        PrivateTmp = true;
        CacheDirectory = "desktop-backup-cold-${name}";
        CacheDirectoryMode = "0700";
        KillMode = "mixed";
        TimeoutStartSec = "2h";
        ExecStopPost = [
          "${python} ${helper} ${helperConfig} recover-native"
          (finish name "cold")
        ];
      }
      // lib.optionalAttrs (destination.environmentFile != null) {
        EnvironmentFile = destination.environmentFile;
      };
    script = (import ../../../../../lib/templates/text.nix) ./scripts/run-cold-backup.sh {
      inherit python;
      inherit helper;
      inherit helperConfig;
      lib_escapeShellArg_name = lib.escapeShellArg name;
    };
  };
in
{
  options.hardware.storage.encryptedRoot.backup = {
    coldUnits = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "[a-zA-Z0-9@_.:-]+\\.(service|mount|timer|socket)");
      default = [ ];
      description = "Complete native writer and activation unit set, ordered consumers before dependencies. Original active states are restored. Empty retains attended rescue mode for legacy cold paths.";
    };
    coldUnmounts = lib.mkOption {
      type = lib.types.listOf credentialPath;
      default = [ ];
      description = "Filesystems which must be unmounted before their backing images are captured.";
    };
    coldPrepareCommand = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Consistent native database export command run after declared writers stop and before file capture.";
    };
    coldPaths = lib.mkOption {
      type = lib.types.listOf credentialPath;
      default = [
        "/etc/libvirt"
        "/var/lib/libvirt"
        "/var/lib/docker"
        "/var/lib/containerd"
      ]
      ++ lib.mapAttrsToList (name: _: "/home/${name}/.local/share/docker") (
        lib.filterAttrs (
          name: user: (user.isNormalUser or false) && user.home == "/home/${name}"
        ) config.users.users
      );
      description = ''
        Durable application state captured by desktop-backup-cold-<destination>
        in attended rescue mode with all VM/container writers stopped. Includes
        libvirt definitions, disks, firmware and vTPM state. Missing paths are
        skipped. Bound mounts or custom external application data need explicit
        inclusion and an application recovery drill.
      '';
    };
    paths = lib.mkOption {
      type = lib.types.listOf credentialPath;
      default = [
        "/home"
        "/etc"
        "/var/lib"
        "/srv/data"
      ];
      description = "Paths in the desktop-files backup set; application databases need consistent exports.";
    };
    exclude = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Caches and live application trees omitted here; the latter require the separate cold backup job.";
    };
    destinations = lib.mkOption {
      default = { };
      description = "Independent Restic destinations for 3-2-1-1-0. Empty means no backups, never implicit protection.";
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }: {
            options = {
              repositoryFile = lib.mkOption {
                type = credentialPath;
                description = "Private runtime file containing the repository URL or path.";
              };
              passwordFile = lib.mkOption {
                type = credentialPath;
                description = "Private runtime Restic password file.";
              };
              environmentFile = lib.mkOption {
                type = lib.types.nullOr credentialPath;
                default = null;
                description = "Private provider credentials, if needed.";
              };
              requiredMounts = lib.mkOption {
                type = lib.types.listOf credentialPath;
                default = [ ];
                description = "Actual external mount points that must be mounted before backup or verification.";
              };
              offsite = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Operator-confirmed off-site destination.";
              };
              medium = lib.mkOption {
                type = lib.types.enum [
                  "hdd"
                  "ssd"
                  "object-storage"
                  "tape"
                  "unknown"
                ];
                default = "unknown";
                description = "Operator-confirmed storage medium, separate from the source SSDs.";
              };
              protection = lib.mkOption {
                type = lib.types.enum [
                  "none"
                  "offline"
                  "immutable"
                ];
                default = "none";
                description = "Physical rotation or externally enforced immutability, not something this option creates.";
              };
              failureDomain = lib.mkOption {
                type = lib.types.str;
                default = name;
                description = "Independent device/provider domain; two repositories on one device are one domain.";
              };
              schedule = lib.mkOption {
                type = lib.types.str;
                default = "daily";
                description = "Backup calendar.";
              };
              verificationSchedule = lib.mkOption {
                type = lib.types.str;
                default = "weekly";
                description = "Full repository data read and canary restore calendar.";
              };
              maxAgeHours = lib.mkOption {
                type = lib.types.ints.positive;
                default = 48;
                description = "Backup freshness limit; adjust for rotated offline media.";
              };
              maxVerificationAgeDays = lib.mkOption {
                type = lib.types.ints.positive;
                default = 14;
                description = "Maximum age of integrity and sample restore results.";
              };
              maxColdAgeDays = lib.mkOption {
                type = lib.types.ints.positive;
                default = 7;
                description = "Maximum age of attended cold application backup and its sample restore.";
              };
            };
          }
        )
      );
    };
  };

  config = {
    # Option defaults disappear when any caller defines a list, even mkAfter.
    # Make the baseline a composable definition so host additions retain it.
    hardware.storage.encryptedRoot.backup.exclude = lib.mkBefore defaultExcludes;
    assertions = [
      {
        assertion =
          builtins.length cfg.backup.coldUnits == builtins.length (lib.unique cfg.backup.coldUnits);
        message = "Native backup writer and activation units must be unique.";
      }
      {
        assertion =
          cfg.backup.coldUnits == [ ]
          || !(lib.any (
            path:
            lib.any (prefix: lib.hasPrefix prefix path) [
              "/etc/libvirt"
              "/var/lib/libvirt"
              "/var/lib/docker"
              "/var/lib/containerd"
              "/var/lib/containers"
              "/var/lib/lxc"
              "/var/lib/incus"
            ]
            || builtins.match "/home/[^/]+/\\.local/share/(docker|containers)(/.*)?" path != null
          ) cfg.backup.coldPaths);
        message = "Native writer quiescence cannot certify VM or container cold paths; retain rescue mode for those datasets.";
      }
      {
        assertion =
          cfg.backup.coldPrepareCommand == [ ]
          || lib.hasPrefix "/" (builtins.head cfg.backup.coldPrepareCommand);
        message = "Native backup preparation needs an absolute executable.";
      }
    ]
    ++ lib.concatLists (
      lib.mapAttrsToList (name: destination: [
        {
          assertion = builtins.match "[a-z][a-z0-9-]*" name != null;
          message = "Backup destination names must be lowercase service-safe identifiers.";
        }
        {
          assertion = lib.all (path: !lib.hasPrefix "/nix/store/" path) (
            [
              destination.repositoryFile
              destination.passwordFile
            ]
            ++ lib.optional (destination.environmentFile != null) destination.environmentFile
          );
          message = "Restic credentials and repository files must remain outside the Nix store.";
        }
        {
          assertion =
            builtins.elem "/var/lib" cfg.backup.paths
            || builtins.elem "/var/lib/desktop-storage" cfg.backup.paths;
          message = "Desktop backups must include the restore canary under /var/lib/desktop-storage.";
        }
      ]) destinations
    );
    # Retire the named transitional overrides once the declarative units are
    # installed. Otherwise an older ExecStart or RAM cap can survive activation.
    # Keep arbitrary operator drop-ins and property overrides untouched.
    system.activationScripts.desktopBackupPolicyCleanup = lib.mkIf cfg.enable {
      deps = [ "etc" ];
      text =
        lib.concatMapStringsSep "\n"
          (unit: ''
            ${pkgs.coreutils}/bin/rm -f -- \
              /etc/systemd/system.control/${unit}.d/80-recurring-memory-fix.conf \
              /etc/systemd/system.control/${unit}.d/90-backup-policy-preview.conf \
              /run/systemd/system/${unit}.d/90-maintenance-stop.conf
          '')
          (
            lib.concatMap (name: [
              "restic-backups-${jobName name}.service"
              "desktop-backup-verify-${name}.service"
              "desktop-backup-cold-${name}.service"
            ]) (lib.attrNames destinations)
          );
    };
    services.restic.backups = lib.mkIf cfg.enable (
      lib.mapAttrs' (
        name: destination: lib.nameValuePair (jobName name) (resticJob name destination)
      ) destinations
    );
    systemd.services = lib.mkIf cfg.enable (
      lib.mapAttrs' (
        name: destination:
        lib.nameValuePair "restic-backups-${jobName name}" {
          requires = lib.optional cfg.capacity.enable "desktop-storage-cache-ready.service";
          after = lib.optional cfg.capacity.enable "desktop-storage-cache-ready.service";
          environment = lib.mkIf cfg.capacity.enable {
            RESTIC_CACHE_DIR = lib.mkForce "/srv/data/cache/restic/${name}";
            TMPDIR = "/srv/data/cache/restic/tmp";
          };
          path = [
            pkgs.util-linux
            config.programs.ssh.package
          ];
          unitConfig.RequiresMountsFor = [
            "/srv/data"
            "/srv/data/work"
          ]
          ++ destination.requiredMounts;
          serviceConfig = memoryBudget // {
            UMask = "0077";
            Nice = 15;
            IOSchedulingClass = "idle";
            ExecStartPost = [ (stamp name "backup") ];
            ExecStopPost = [ (finish name "backup") ];
          };
        }
      ) destinations
      // lib.mapAttrs' (
        name: destination: lib.nameValuePair "desktop-backup-verify-${name}" (verifyJob name destination)
      ) destinations
      // lib.mapAttrs' (
        name: destination: lib.nameValuePair "desktop-backup-cold-${name}" (coldJob name destination)
      ) destinations
    );
    systemd.timers = lib.mkIf cfg.enable (
      lib.mapAttrs' (
        name: destination:
        lib.nameValuePair "desktop-backup-verify-${name}" {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = destination.verificationSchedule;
            Persistent = true;
            RandomizedDelaySec = "1h";
          };
        }
      ) destinations
    );
    environment.systemPackages = [
      pkgs.restic
      checkPackage
    ];
    environment.etc."desktop-storage/backup-policy.json".source = helperConfig;
    system.build.desktopBackupCheck = checkPackage;
  };
}
