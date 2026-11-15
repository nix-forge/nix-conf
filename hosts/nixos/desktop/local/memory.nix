{
  config,
  lib,
  pkgs,
  ...
}:
let
  desktopUid = toString config.users.users.ianmh.uid;
  workload = config.workstation.workloads;
in
{
  # Cold interactive pages exhausted the original swap during validation.
  # Keep this fallback inside the encrypted root and retain all RAM ceilings.
  swapDevices = lib.mkIf config.hardware.storage.encryptedRoot.enable [
    {
      device = "/swap/workstation";
      size = 8 * 1024;
      priority = -1;
    }
  ];

  # Other modules extend this option, which replaces its option-level default.
  hardware.storage.encryptedRoot.backup.exclude =
    lib.mkIf config.hardware.storage.encryptedRoot.enable
      (lib.mkAfter [ "/swap" ]);

  assertions = [
    {
      assertion =
        !config.hardware.storage.encryptedRoot.enable
        || lib.elem "/swap" config.hardware.storage.encryptedRoot.backup.exclude;
      message = "The workstation swap subvolume must be excluded from backups.";
    }
  ];

  systemd = {
    tmpfiles.rules = [
      # Both root backups and user bulk commands participate. A root-owned
      # parent prevents users replacing the lock with a privileged symlink.
      "d /run/workstation-workloads 0750 root ${config.users.users.ianmh.group} - -"
      "f /run/workstation-workloads/bulk.lock 0660 root ${config.users.users.ianmh.group} - -"
    ];
    # Protection must be assigned at each ancestor. These are best-effort
    # reclaim protections, not preallocated RAM or immunity from the OOM killer.
    slices = {
      user.sliceConfig.MemoryLow = "6G";
      "user-${desktopUid}".sliceConfig.MemoryLow = "6G";
    };
    services = {
      mkswap-swap-workstation = lib.mkIf config.hardware.storage.encryptedRoot.enable {
        # Swap precedes local-fs.target, while global tmpfiles runs after it.
        # Waiting for that service creates a cycle which can discard the
        # security-wrapper mount and prevent both graphical and SSH login.
        # Prepare only our directory here, after the upstream RequiresMountsFor
        # dependency has made its filesystem available, including on first boot.
        preStart = ''
          ${lib.getExe' pkgs.systemd "systemd-tmpfiles"} --create ${pkgs.writeText "workstation-swap.conf" "v /swap 0700 root root - -\n"}
        '';
      };
      "user@${desktopUid}" = {
        overrideStrategy = "asDropin";
        serviceConfig.MemoryLow = "6G";
      };
      # The daemon RAM/swap limits remain in system.nix.
      nix-daemon.serviceConfig.IOWeight = 50;
    };

    user.slices = {
      background.sliceConfig.IOWeight = 25;
      session.sliceConfig = {
        MemoryLow = "2G";
        CPUWeight = 200;
        IOWeight = 200;
      };
      app.sliceConfig.MemoryLow = "4G";
      # The runner's scopes are siblings of interactive applications. Monitor
      # only this subtree: oomd must never select a desktop application scope.
      "background-workload" = {
        description = "Queued workstation development workloads";
        sliceConfig = {
          MemoryHigh = workload.aggregate.highMiB * 1024 * 1024;
          MemoryMax = workload.aggregate.memoryMiB * 1024 * 1024;
          MemorySwapMax = workload.aggregate.swapMiB * 1024 * 1024;
          CPUWeight = 25;
          IOWeight = 25;
          ManagedOOMMemoryPressure = "kill";
          ManagedOOMMemoryPressureLimit = "60%";
        };
      };
    };
    oomd.enable = true;

    # Keep core dumps bounded on the encrypted root filesystem.
    coredump.settings.Coredump = {
      ProcessSizeMax = "256M";
      Storage = "external";
      ExternalSizeMax = "256M";
      MaxUse = "1G";
      KeepFree = "4G";
    };
  };

  # Retire the scoped repair only when this cycle-free configuration activates.
  # It lets the already-booted generation recover without switching unrelated
  # pending configuration. Leave any replacement owned by another task intact.
  system.activationScripts.desktopBootReliabilityCleanup.text = ''
    source ${./scripts/retire-boot-repair.sh} \
      /etc/systemd/system.control/mkswap-swap-workstation.service \
      /nix/var/nix/gcroots/desktop-boot-reliability
  '';

  # Preserve unexpected unmanaged files rather than blocking activation or
  # overwriting them. Each backup has a private, unique directory.
  home-manager.backupCommand = lib.getExe (
    pkgs.writeShellApplication {
      name = "home-manager-preserve-file";
      runtimeInputs = [ pkgs.coreutils ];
      text = builtins.readFile ./scripts/home-manager-preserve-file.sh;
    }
  );

  # Build and inspect this policy without rebuilding unrelated desktop
  # applications. The manifest contains the actual generated configuration.
  system.build.workstationTask = config.home-manager.users.ianmh.lib.workstationTask;

  system.build.desktopMemoryPolicy = pkgs.linkFarm "desktop-memory-policy" (
    [
      {
        name = "runner";
        path = config.system.build.workstationTask;
      }
      {
        name = "workload-policy.json";
        path = config.system.build.workstationWorkloadPolicy;
      }
      {
        name = "backup-command";
        path = config.home-manager.backupCommand;
      }
      {
        name = "coredump.conf";
        path = config.environment.etc."systemd/coredump.conf".source;
      }
      {
        name = "preserve-configuration.sh";
        path = pkgs.writeText "preserve-configuration.sh" config.home-manager.users.ianmh.home.activation.preserveConfigurationConflicts.data;
      }
      {
        name = "backup-policy-cleanup.sh";
        path = pkgs.writeText "desktop-backup-policy-cleanup.sh" (
          config.system.activationScripts.desktopBackupPolicyCleanup.text or ""
        );
      }
      {
        name = "manifest.json";
        path = pkgs.writeText "desktop-memory-manifest.json" (
          builtins.toJSON {
            inherit (config.systemd.coredump.settings) Coredump;
            temporaryStorage = {
              useTmpfs = config.boot.tmp.useTmpfs;
              cleanOnBoot = config.boot.tmp.cleanOnBoot;
            };
            swap = map (s: {
              inherit (s)
                device
                realDevice
                priority
                randomEncryption
                ;
            }) config.swapDevices;
            sleep = config.systemd.sleep.settings.Sleep;
            assertions = map (a: a.message) (lib.filter (a: !a.assertion) config.assertions);
            backups = lib.mapAttrs (name: job: {
              inherit (job) exclude;
              inherit (config.systemd.services."restic-backups-${name}".serviceConfig)
                MemoryHigh
                MemoryMax
                MemorySwapMax
                ;
            }) config.services.restic.backups;
          }
        );
      }
    ]
    ++
      map
        (name: {
          name = "user/${name}.slice";
          path = "${config.systemd.user.units."${name}.slice".unit}/${name}.slice";
        })
        [
          "session"
          "app"
          "background"
          "background-workload"
        ]
    ++
      map
        (name: {
          name = "system/${name}";
          path = "${config.systemd.units.${name}.unit}/${name}";
        })
        [
          "user.slice"
          "user-${desktopUid}.slice"
          "user@${desktopUid}.service"
          "nix-daemon.service"
        ]
    ++
      map
        (name: {
          name = "user/${name}.service.d/60-memory.conf";
          path =
            config.home-manager.users.ianmh.xdg.configFile."systemd/user/${name}.service.d/60-memory.conf".source;
        })
        [
          "hypridle"
          "noctalia"
        ]
    ++ lib.concatLists (
      lib.mapAttrsToList (name: job: [
        {
          name = "backups/${name}/restic";
          path = job.package;
        }
        {
          name = "backups/${name}/excludes";
          path = pkgs.writeText "${name}-backup-excludes" (lib.concatStringsSep "\n" job.exclude + "\n");
        }
        {
          name = "backups/${name}/unit";
          path = "${
            config.systemd.units."restic-backups-${name}.service".unit
          }/restic-backups-${name}.service";
        }
      ]) config.services.restic.backups
    )
    ++ lib.concatLists (
      lib.mapAttrsToList (name: _: [
        {
          name = "backups/desktop-${name}/verify-unit";
          path = "${
            config.systemd.units."desktop-backup-verify-${name}.service".unit
          }/desktop-backup-verify-${name}.service";
        }
        {
          name = "backups/desktop-${name}/cold-unit";
          path = "${
            config.systemd.units."desktop-backup-cold-${name}.service".unit
          }/desktop-backup-cold-${name}.service";
        }
      ]) config.hardware.storage.encryptedRoot.backup.destinations
    )
    ++ [
      {
        name = "workstation-tmpfiles.conf";
        path = pkgs.writeText "workstation-workloads-tmpfiles.conf" (
          lib.concatStringsSep "\n" (
            lib.filter (rule: lib.hasInfix "/run/workstation-workloads" rule) config.systemd.tmpfiles.rules
          )
          + "\n"
        );
      }
      {
        name = "user/app-org.chromium.Chromium-.scope.d/50-oom-policy.conf";
        path =
          config.home-manager.users.ianmh.xdg.configFile."systemd/user/app-org.chromium.Chromium-.scope.d/50-oom-policy.conf".source;
      }
      {
        name = "user/app-org.chromium.Chromium-.scope.d/70-swap-headroom.conf";
        path =
          config.home-manager.users.ianmh.xdg.configFile."systemd/user/app-org.chromium.Chromium-.scope.d/70-swap-headroom.conf".source;
      }
    ]
  );
}
