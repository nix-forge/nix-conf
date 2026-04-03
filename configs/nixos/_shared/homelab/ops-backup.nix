{
  profile ? "home-server",
}:
{
  pkgs,
  ...
}:
let
  stack = import ./stack-values.nix { inherit profile; };
in
{
  systemd.services.homelab-backup = {
    description = "Run homelab restic backup";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Group = "root";
    };
    path = with pkgs; [ restic ];
    script = ''
      set -euo pipefail

      repo=/var/backup/restic/homelab
      passfile=/var/backup/restic/.password

      mkdir -p /var/backup/restic
      if [ ! -f "$passfile" ]; then
        umask 077
        head -c 48 /dev/urandom | base64 > "$passfile"
      fi

      export RESTIC_REPOSITORY="$repo"
      export RESTIC_PASSWORD_FILE="$passfile"

      if [ ! -e "$repo/config" ]; then
        restic init
      fi

      restic backup \
        ${stack.stackRoot}/data \
        /var/lib/jellyfin \
        /var/lib/sonarr \
        /var/lib/radarr \
        /var/lib/lidarr \
        /var/lib/readarr \
        /var/lib/prowlarr \
        /var/lib/qbittorrent \
        /var/lib/nzbget \
        /var/lib/seerr \
        /var/lib/vaultwarden \
        --exclude ${stack.stackRoot}/data/torrents/incomplete \
        --exclude ${stack.stackRoot}/data/usenet/incomplete

      restic forget --prune --keep-daily 7 --keep-weekly 4 --keep-monthly 6
    '';
  };

  systemd.timers.homelab-backup = {
    description = "Run daily homelab backup";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "30m";
      Persistent = true;
      Unit = "homelab-backup.service";
    };
  };
}
