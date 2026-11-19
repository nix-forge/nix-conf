{
  config,
  lib,
  myLib,
  pkgs,
  ...
}:
let
  checkedShellText = myLib.writers.checkedShellText { inherit pkgs; };
  writeShellApplication = myLib.writers.writeShellApplication { inherit pkgs; };
  storageRuntime =
    (import ../../../../../flake/runtime-packages.nix { inherit pkgs; }).desktopStorageRuntime;
  cfg = config.hardware.storage.encryptedRoot;
  inherit (cfg) capacity;
  inherit (import ./.storage-roles.nix)
    bulkLockPath
    cacheRoot
    dataMount
    gamesMount
    homelabMount
    resticCacheRoot
    runtimeDirectory
    scratchRoot
    vmImagesMount
    workMount
    ;
  workspaceBackupPath = "${config.home-manager.users.ianmh.xdg.stateHome}/workspace-services/backups";
  workspaceBackupStorage = "${dataMount}/workspace-backups";
  workspaceUser = config.users.users.ianmh;
  gib = value: value * 1024 * 1024 * 1024;
  bytes =
    default: description:
    lib.mkOption {
      type = lib.types.ints.positive;
      inherit default description;
    };
  limits = path: warning: critical: recovery: criticalRecovery: aliases: {
    inherit path aliases;
    requireMount = true;
    warningBytes = gib warning;
    criticalBytes = gib critical;
    warningRecoveryBytes = gib recovery;
    criticalRecoveryBytes = gib criticalRecovery;
    admissionBytes = gib warning;
  };
  filesystems = [
    (limits "/" capacity.warningGiB capacity.criticalGiB capacity.warningRecoveryGiB
      capacity.criticalRecoveryGiB
      [ ]
    )
    (limits dataMount 200 100 250 125 [
      gamesMount
      vmImagesMount
    ])
  ]
  ++ lib.optional (config.hardware.storage.homelabHdd.enable or false) (
    limits homelabMount 1024 512 1152 768 [ ]
  );
  policy = pkgs.writeText "desktop-storage-capacity.json" (
    builtins.toJSON {
      inherit filesystems;
      collectBelowBytes = gib capacity.collectBelowGiB;
      collectTargetBytes = gib capacity.collectTargetGiB;
      defaultAdditionalBytes = gib capacity.defaultAdditionalGiB;
      minimumMemoryAvailableBytes = gib 14;
      stateDirectory = "/var/lib/desktop-storage";
      cache = {
        mount = dataMount;
        root = cacheRoot;
      };
      bulkLock = bulkLockPath;
      generations = {
        profile = "/nix/var/nix/profiles/system";
        currentSystem = "/run/current-system";
        bootedSystem = "/run/booted-system";
        storeDirectory = "/nix/store";
        pinsDirectory = "/nix/var/nix/gcroots/desktop-generation-pins";
        nixEnv = lib.getExe' config.nix.package "nix-env";
        nixStore = lib.getExe' config.nix.package "nix-store";
        keepCount = 10;
        keepDays = 14;
      };
      nixStore = lib.getExe' config.nix.package "nix-store";
      retrySeconds = 4 * 60 * 60;
      retryDropBytes = gib 10;
      collectorStaleSeconds = 2 * 60 * 60;
      cacheBudgets = [
        {
          path = resticCacheRoot;
          warningBytes = gib 64;
        }
      ];
    }
  );
  program = lib.getExe' storageRuntime "desktop-storage-capacity";
  command = writeShellApplication {
    name = "desktop-storage-capacity";
    runtimeInputs = [
      pkgs.util-linux
      pkgs.coreutils
    ];
    text = ''exec ${program} --policy ${policy} "$@"'';
  };
  retentionProgram = lib.getExe' storageRuntime "desktop-storage-retention";
  retention = writeShellApplication {
    name = "desktop-storage-retention";
    text = ''exec ${retentionProgram} --policy ${policy} "$@"'';
  };
  taskRetirementPolicy = pkgs.writeText "desktop-task-retirement.json" (
    builtins.toJSON { inherit dataMount scratchRoot; }
  );
  taskRetirement = writeShellApplication {
    name = "desktop-task-retire";
    runtimeInputs = [ pkgs.util-linux ];
    text = ''exec ${lib.getExe' storageRuntime "desktop-task-retire"} --policy ${taskRetirementPolicy} "$@"'';
  };
  installer = writeShellApplication {
    name = "prepare-desktop-installer";
    runtimeInputs = [ pkgs.git ];
    text = ''exec ${lib.getExe' storageRuntime "prepare-desktop-installer"} "$@"'';
  };
  taskCache = writeShellApplication {
    name = "desktop-task-cache";
    runtimeInputs = [ pkgs.util-linux ];
    text = ''
      if [[ $# != 1 ]]; then echo 'Usage: desktop-task-cache UNIQUE_TASK_OWNER' >&2; exit 2; fi
      exec ${lib.getExe taskRetirement} --create-cache --owner "$1"
    '';
  };
in
{
  options.hardware.storage.encryptedRoot.capacity = {
    enable = lib.mkEnableOption "one coordinated desktop storage capacity policy" // {
      default = cfg.enable;
    };
    collectBelowGiB = bytes 200 "Start Nix reclamation below this available-space threshold.";
    collectTargetGiB = bytes 250 "Target available space after Nix reclamation.";
    warningGiB = bytes 150 "Available system space below which to warn and reject ordinary new work.";
    warningRecoveryGiB = bytes 175 "Available system space required to clear a capacity warning.";
    criticalGiB = bytes 75 "Available system space below which capacity is critical.";
    criticalRecoveryGiB = bytes 100 "Available system space required to leave the critical state.";
    defaultAdditionalGiB = bytes 32 "Conservative additional peak disk estimate for undeclared ordinary jobs.";
  };
  config = lib.mkIf capacity.enable {
    # Keep the adapter's existing private path while storing dumps outside
    # the home snapshot. The automount blocks writes if the data disk is absent.
    fileSystems.${workspaceBackupPath} = {
      device = workspaceBackupStorage;
      fsType = "none";
      options = [
        "bind"
        "nofail"
        "x-systemd.automount"
        "x-systemd.requires=desktop-workspace-backups-ready.service"
      ];
    };
    systemd.services.desktop-workspace-backups-ready = {
      description = "Prepare the data SSD workspace backup subvolume";
      bindsTo = [ "srv-data.mount" ];
      after = [ "srv-data.mount" ];
      path = [
        pkgs.btrfs-progs
        pkgs.coreutils
        pkgs.util-linux
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        UMask = "0077";
      };
      script = ''
        set -eu
        mountpoint -q ${lib.escapeShellArg dataMount}
        directory=${lib.escapeShellArg workspaceBackupStorage}
        if [[ ! -e $directory ]]; then
          btrfs subvolume create "$directory"
        fi
        [[ ! -L $directory ]]
        btrfs subvolume show "$directory" >/dev/null
        chown ${lib.escapeShellArg "${workspaceUser.name}:${workspaceUser.group}"} "$directory"
        chmod 0700 "$directory"
      '';
    };
    # The file backup already includes the data SSD source of this bind mount.
    hardware.storage.encryptedRoot.backup.exclude = [ workspaceBackupPath ];

    assertions = [
      {
        assertion =
          !config.nix.gc.automatic
          && !(config.programs.nh.clean.enable or false)
          && config.nix.determinateNixdSettings.garbageCollector.strategy == "disabled";
        message = "The desktop capacity policy must be the only scheduled Nix collector.";
      }
      {
        assertion =
          capacity.collectTargetGiB > capacity.collectBelowGiB
          && capacity.collectBelowGiB > capacity.warningRecoveryGiB
          && capacity.warningRecoveryGiB > capacity.warningGiB
          && capacity.warningGiB > capacity.criticalRecoveryGiB
          && capacity.criticalRecoveryGiB > capacity.criticalGiB;
        message = "Storage collection, admission and alert watermarks must leave ordered recovery margins.";
      }
    ];
    nix.settings = {
      # The scheduled collector owns proactive reclamation and its cooldown.
      # Nix's per-connection collector cannot share that cooldown: using the
      # same watermark repeatedly stalls builds when retained roots prevent
      # reclamation. Keep native collection as an emergency backstop, with
      # headroom above the critical floor.
      min-free = gib capacity.criticalRecoveryGiB;
      max-free = gib capacity.collectTargetGiB;
    };
    # The native backstop and scheduled collector share Nix's GC lock.
    # Disable Nixd's independent collector to avoid another scheduler.
    nix.determinateNixdSettings.garbageCollector.strategy = "disabled";
    environment.systemPackages = [
      command
      retention
      taskRetirement
      taskCache
      installer
    ];
    environment.etc."desktop-storage/capacity.json".source = policy;
    system = {
      activationScripts.desktopStoragePreviewCleanup = {
        deps = [ "etc" ];
        text = ''
          ${lib.getExe'
            (import ../../../../../flake/runtime-packages.nix { inherit pkgs; }).desktopStorageRuntime
            "desktop-storage-retire-preview"
          }
        '';
      };
      build = {
        desktopStorageCapacity = command;
        desktopInstallerPreparation = installer;
        desktopStorageRetention = retention;
        desktopStorageCapacityPolicy = policy;
        desktopStorageCommands = pkgs.symlinkJoin {
          name = "desktop-storage-tools";
          paths = [
            command
            retention
            taskRetirement
            taskCache
          ];
        };
        desktopStoragePreview = pkgs.symlinkJoin {
          name = "desktop-storage-preview";
          paths = [ config.system.build.desktopStorageRootPreview ];
        };
        desktopStorageRootPreview = pkgs.symlinkJoin {
          name = "desktop-storage-root-preview";
          paths = [
            config.system.build.desktopStorageCommands
            (lib.findFirst (
              package: lib.getName package == "desktop-storage-status"
            ) null config.environment.systemPackages)
            (pkgs.symlinkJoin {
              name = "desktop-storage-restic-wrappers";
              paths = lib.filter (
                package: lib.hasPrefix "restic-desktop-" (lib.getName package)
              ) config.environment.systemPackages;
            })
          ];
        };
        # These selected artifacts support a scoped rollout without activating
        # unrelated pending applications.
        desktopStorageRollout = pkgs.linkFarm "desktop-storage-rollout" (
          [
            {
              name = "preview";
              path = config.system.build.desktopStoragePreview;
            }
            {
              name = "root-preview";
              path = config.system.build.desktopStorageRootPreview;
            }
            {
              name = "commands";
              path = config.system.build.desktopStorageCommands;
            }
            {
              name = "capacity.json";
              path = policy;
            }
            {
              name = "health";
              path = lib.findFirst (
                package: lib.getName package == "desktop-storage-status"
              ) null config.environment.systemPackages;
            }
            {
              name = "public-nix.conf";
              path = config.environment.etc."nix/nix.conf".source;
            }
            {
              name = "nixd.json";
              path = config.environment.etc."determinate/config.json".source;
            }
            {
              name = "root-nix.conf";
              path = config.system.build.nixRootCredentials;
            }
            {
              name = "user-nix.conf";
              path = config.home-manager.users.ianmh.xdg.configFile."nix/nix.conf".source;
            }
            {
              name = "install-root-credentials.sh";
              path = config.system.build.nixRootCredentialInstaller;
            }
            {
              name = "restic-wrappers";
              path = pkgs.symlinkJoin {
                name = "desktop-storage-restic-wrappers";
                paths = lib.filter (
                  package: lib.hasPrefix "restic-desktop-" (lib.getName package)
                ) config.environment.systemPackages;
              };
            }
            {
              name = "cache-environments.json";
              path = pkgs.writeText "desktop-restic-cache-environments.json" (
                builtins.toJSON (
                  lib.mapAttrs (
                    _: service:
                    lib.filterAttrs (
                      name: _:
                      lib.elem name [
                        "RESTIC_CACHE_DIR"
                        "TMPDIR"
                      ]
                    ) service.environment
                  ) (lib.filterAttrs (name: _: lib.hasPrefix "restic-backups-desktop-" name) config.systemd.services)
                )
              );
            }
          ]
          ++
            map
              (name: {
                name = "system/${name}";
                path = "${config.systemd.units.${name}.unit}/${name}";
              })
              [
                "desktop-storage-collect.service"
                "desktop-storage-collect.timer"
                "desktop-generation-retention.service"
                "desktop-generation-retention.timer"
                "desktop-storage-cache-ready.service"
                "desktop-storage-health.service"
                "nix-daemon.service"
                "desktop-snapshot-home-timeline.service"
                "desktop-snapshot-data-timeline.service"
                "desktop-snapshot-work-timeline.service"
              ]
        );
      };
    };
    systemd = {
      services = {
        desktop-storage-cache-ready = {
          description = "Prepare snapshot-excluded regenerable cache subvolumes";
          wantedBy = [ "multi-user.target" ];
          requires = [ "desktop-data-ready.service" ];
          after = [ "desktop-data-ready.service" ];
          unitConfig.RequiresMountsFor = [
            dataMount
            workMount
          ];
          path = [
            pkgs.btrfs-progs
            pkgs.coreutils
            pkgs.util-linux
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            UMask = "0077";
          };
          script = checkedShellText {
            name = "prepare-cache-subvolumes";
            text = (''
              # shellcheck shell=bash
              set -euo pipefail
              mountpoint -q ${lib.escapeShellArg dataMount}
              mountpoint -q ${lib.escapeShellArg workMount}
              for directory in ${lib.escapeShellArg cacheRoot} ${lib.escapeShellArg scratchRoot}; do
                if [[ ! -e $directory ]]; then btrfs subvolume create "$directory"; fi
                # A normal restored directory is not a snapshot boundary. Refuse it.
                btrfs subvolume show "$directory" >/dev/null
                chown root:root "$directory"
                tag="$directory/CACHEDIR.TAG"
                signature='Signature: 8a477f597d28d172789f06886806bc55'
                if [[ -e $tag || -L $tag ]]; then
                  [[ ! -L $tag && -f $tag && $(head -c 43 "$tag") == "$signature" ]]
                else
                  printf '%s\n# Regenerable caches and task scratch only.\n' "$signature" >"$tag"
                fi
                chmod 0644 "$tag"
              done
              chmod 0700 ${lib.escapeShellArg cacheRoot}
              chmod 0755 ${lib.escapeShellArg scratchRoot}
              install -d -m 0700 ${lib.escapeShellArg resticCacheRoot} ${lib.escapeShellArg "${resticCacheRoot}/tmp"}
            '')
            + lib.concatMapStringsSep "\n" (
              user:
              "install -d -m 0700 -o ${lib.escapeShellArg user.name} -g ${
                lib.escapeShellArg (if user.group == null then "users" else user.group)
              } ${lib.escapeShellArg "${scratchRoot}/${user.name}"}"
            ) (builtins.attrValues (lib.filterAttrs (_: user: user.isNormalUser) config.users.users));
          };
        };
        desktop-storage-collect = {
          description = "Reclaim dead Nix paths under the desktop capacity policy";
          after = [ "nix-daemon.service" ];
          unitConfig.RequiresMountsFor = [ "/nix" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${lib.getExe command} collect";
            TimeoutStartSec = "30min";
            TimeoutStopSec = "5min";
            KillMode = "control-group";
            UMask = "0077";
            Nice = 15;
            IOWeight = 25;
            MemoryHigh = "384M";
            MemoryMax = "512M";
            # The GC itself uses the separately contained Nix daemon. The client
            # takes the storage maintenance lock before requesting it.
            ReadWritePaths = [
              "/var/lib/desktop-storage"
              runtimeDirectory
            ];
            ProtectSystem = "strict";
            ProtectHome = "read-only";
            PrivateTmp = true;
          };
        };
        desktop-generation-retention = {
          description = "Retire system generations while preserving recovery roots";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${lib.getExe retention} retire";
            TimeoutStartSec = "30min";
            UMask = "0077";
            Nice = 15;
            MemoryMax = "512M";
          };
        };
      };
      timers = {
        desktop-generation-retention = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "weekly";
            Persistent = true;
            RandomizedDelaySec = "30m";
          };
        };
        desktop-storage-collect = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "2m";
            OnUnitActiveSec = "15m";
            RandomizedDelaySec = "1m";
          };
        };
      };
    };
  };
}
