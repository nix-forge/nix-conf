{
  config,
  lib,
  pkgs,
  ...
}:
{
  systemd = {
    # Protection must be assigned at each ancestor. These are best-effort
    # reclaim protections, not preallocated RAM or immunity from the OOM killer.
    slices = {
      user.sliceConfig.MemoryLow = "6G";
      "user-1000".sliceConfig.MemoryLow = "6G";
    };
    services = {
      "user@1000" = {
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
          MemoryHigh = 8 * 1024 * 1024 * 1024;
          MemoryMax = 10 * 1024 * 1024 * 1024;
          MemorySwapMax = 2 * 1024 * 1024 * 1024;
          CPUWeight = 25;
          IOWeight = 25;
          ManagedOOMMemoryPressure = "kill";
          ManagedOOMMemoryPressureLimit = "60%";
        };
      };
    };
    oomd.enable = true;

    # Memory dumps may contain credentials. Until root storage is encrypted,
    # retain only the crash log; Storage=none alone still writes temporary cores.
    coredump.settings.Coredump = {
      ProcessSizeMax = if config.hardware.storage.encryptedRoot.enable then "256M" else "0";
      Storage = if config.hardware.storage.encryptedRoot.enable then "external" else "none";
      ExternalSizeMax = "256M";
      MaxUse = "1G";
      KeepFree = "4G";
    };
  };

  # Preserve unexpected unmanaged files rather than blocking activation or
  # overwriting them. Each backup has a private, unique directory.
  home-manager.backupCommand = lib.getExe (
    pkgs.writeShellApplication {
      name = "home-manager-preserve-file";
      runtimeInputs = [ pkgs.coreutils ];
      text = ''
        if [[ $# != 1 || ! -e "$1" && ! -L "$1" ]]; then
          echo "Expected one existing Home Manager conflict path" >&2
          exit 1
        fi
        umask 077
        backup_root="''${XDG_STATE_HOME:-$HOME/.local/state}/home-manager/conflicts"
        mkdir -p -- "$backup_root"
        backup_dir=$(mktemp -d "$backup_root/backup.XXXXXXXX")
        printf '%s\n' "$1" > "$backup_dir/original-path"
        # Dereference file symlinks so garbage collection cannot erase the
        # preserved content of a manually installed Nix-store configuration.
        if [[ -L "$1" && ! -e "$1" ]]; then
          printf 'Symlink target was unavailable at backup time.\n' > "$backup_dir/content-unavailable"
        else
          cp -aL -- "$1" "$backup_dir/content"
        fi
        mv -- "$1" "$backup_dir/original"
        printf 'Preserved unmanaged configuration in %s\n' "$backup_dir" >&2
      '';
    }
  );

  # Build and inspect this policy without rebuilding unrelated desktop
  # applications. The manifest contains the actual generated configuration.
  system.build.desktopMemoryPolicy = pkgs.linkFarm "desktop-memory-policy" (
    [
      {
        name = "runner";
        path =
          lib.findFirst (p: lib.getName p == "workstation-task")
            (throw "desktop memory policy requires the home workload runner")
            config.home-manager.users.ianmh.home.packages;
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
        name = "swap-transition-check";
        path = pkgs.writeShellScript "check-swap-transition" (
          config.system.preSwitchChecks.encryptedSwapTransition or "exit 0"
        );
      }
      {
        name = "preserve-configuration.sh";
        path = pkgs.writeText "preserve-configuration.sh" config.home-manager.users.ianmh.home.activation.preserveConfigurationConflicts.data;
      }
      {
        name = "manifest.json";
        path = pkgs.writeText "desktop-memory-manifest.json" (
          builtins.toJSON {
            inherit (config.systemd.coredump.settings) Coredump;
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
          "user-1000.slice"
          "user@1000.service"
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
  );
}
