{ config, lib, ... }: {
  # Enable the local repository only after both the encrypted system and the
  # separately provisioned USB disk are active. The connected HDD is one
  # failure domain and does not claim offline or off-site protection.
  config =
    lib.mkIf (config.hardware.storage.encryptedRoot.enable && config.hardware.storage.homelabHdd.enable)
      {
        nixSeal.secrets.homelab-restic-password = {
          phase = "services";
          mode = "0400";
        };
        hardware.storage.encryptedRoot.backup = {
          destinations.homelab = {
            repositoryFile = "/var/lib/desktop-storage/keys/homelab-restic-repository";
            passwordFile = config.nixSeal.secrets.homelab-restic-password.path;
            requiredMounts = [ "/mnt/homelab" ];
            medium = "hdd";
            failureDomain = "homelab-usb-hdd";
            schedule = "Sat *-*-* 03:00:00";
            maxAgeHours = 216;
            verificationSchedule = "*-*-01 04:00:00";
            maxVerificationAgeDays = 35;
          };
          # A list definition replaces the option default, even with mkAfter.
          # Keep the restore canary and durable sources in the backup set.
          paths = [
            "/home"
            "/etc"
            "/var/lib"
            "/srv/data"
            "/root"
          ];
          exclude = lib.mkAfter (
            [
              "/home/*/.config/codex/.tmp"
              "/home/*/.local/share/Trash"
              "/var/lib/desktop-storage/keys"
              "/var/lib/desktop-storage/database-backups"
              "/home/*/.npm"
              "/home/*/.cargo/registry"
              "/home/*/.cargo/git"
              "/home/*/.local/share/pnpm/store"
              "/home/*/.config/codex/plugins/cache"
              "/home/*/.local/state/package-refresh-*/aurral-candidate/pnpm-*"
            ]
            ++
              lib.concatMap
                (
                  base:
                  map (name: "${base}/**/${name}") [
                    "node_modules"
                    ".venv"
                    ".direnv"
                    "__pycache__"
                    ".ruff_cache"
                    ".pytest_cache"
                  ]
                )
                [
                  "/home/*/Developer"
                  "/home/*/Worktrees"
                  "/srv/data/work"
                  "/home/*/.local/state/package-refresh-*"
                ]
          );
        };
        # Native writers are explicitly guarded and resumed by this job. No VM
        # or desktop session shutdown is part of the nightly application set.
        systemd.timers.desktop-backup-cold-homelab =
          lib.mkIf (config.hardware.storage.encryptedRoot.backup.coldUnits != [ ])
            {
              wantedBy = [ "timers.target" ];
              timerConfig = {
                OnCalendar = "*-*-* 03:30:00";
                RandomizedDelaySec = "15m";
                Persistent = true;
              };
            };
      };
}
