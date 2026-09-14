{
  config,
  lib,
  pkgs,
  ...
}:
let
  musicFolder = "/srv/data/media/music";
  backupRoot = "/srv/data/media/.services/music-discovery/backups";
  navidromePort = 4533;
  listenerPort = 4534;
  listenerIPv4 = "192.168.10.178";
  audioMusePort = 8000;
  audioMuseEnvironment = config.nixSeal.secrets.music-discovery-audiomuse-settings.path;
  navidromeEnvironment = config.nixSeal.secrets.music-discovery-navidrome-settings.path;
  bootstrapAudioMuseCredential = "/run/music-discovery-bootstrap-credential/audiomuse-api-token";
  audioMuseHouseholdApproval = "${backupRoot}/.audiomuse-household-approved";
  navidromeSettings = {
    Address = "127.0.0.1";
    Port = navidromePort;
    MusicFolder = musicFolder;
    DataFolder = "/var/lib/navidrome";
    CacheFolder = "/var/cache/navidrome";
    ScanSchedule = "@every 1h";
    LogLevel = "info";

    # AudioMuse handles local sonic similarity first. ListenBrainz and Deezer
    # retain broad metadata fallbacks without requiring shared API secrets.
    Agents = "audiomuseai,listenbrainz,deezer";
    LastFM.Enabled = false;
    ListenBrainz.Enabled = true;
    EnableExternalServices = true;

    EnableInsightsCollector = false;
    EnableLogRedacting = true;
    EnforceNonRootUser = true;
    EnableSharing = false;
    EnableNowPlaying = false;
    EnableScrobbleHistory = true;
    DefaultPlaylistPublicVisibility = false;
    EnableM3UExternalAlbumArt = false;
    EnableReplayGain = true;
    EnableScheduledDBAnalyze = true;
    EnableUserEditing = true;
    DefaultDownsamplingFormat = "opus";
    TranscodingCacheSize = "4GiB";
    Transcoding = {
      EnableCancellation = true;
      MaxConcurrent = 4;
      MaxConcurrentPerUser = 2;
    };
    ImageCacheSize = "1GiB";
    SessionTimeout = "48h";
    AuthRequestLimit = 5;
    AuthWindowLength = "20s";

    Backup = {
      Path = "${backupRoot}/navidrome";
      Schedule = "0 4 * * *";
      Count = 14;
    };
    Plugins = {
      Enabled = true;
      AutoReload = false;
      LogLevel = "warn";
      CacheSize = "200MB";
    };
    # Keep star ratings personal instead of exposing an average across listener
    # accounts through Subsonic clients.
    Subsonic.EnableAverageRating = false;
  };
  # Reuse the merged settings so bootstrap sees module-provided values such as
  # the plugin directory from services.navidrome.plugins.
  navidromeConfig =
    (pkgs.formats.json { }).generate "navidrome.json"
      config.services.navidrome.settings;
  bootstrap = pkgs.writeShellApplication {
    name = "music-discovery-bootstrap";
    runtimeInputs = [
      config.services.navidrome.finalPackage
      pkgs.coreutils
      pkgs.curl
      pkgs.expect
      pkgs.jq
    ];
    text = ''
      set -eu

      ready=0
      for _ in $(seq 1 60); do
        if curl --fail --silent --output /dev/null http://127.0.0.1:${toString navidromePort}/ping; then
          ready=1
          break
        fi
        sleep 1
      done
      if [ "$ready" -ne 1 ]; then
        echo "Navidrome did not become ready within 60 seconds" >&2
        exit 1
      fi

      users_json="$(navidrome --configfile ${navidromeConfig} user list --format json)"
      has_user() {
        jq --exit-status --arg user "$1" \
          'map(.userName // .username // .UserName) | index($user) != null' \
          <<<"$users_json" >/dev/null
      }
      create_user() {
        local username="$1"
        local password="$2"
        local role="$3"
        MUSIC_DISCOVERY_USERNAME="$username" \
        MUSIC_DISCOVERY_PASSWORD="$password" \
        MUSIC_DISCOVERY_ROLE="$role" \
          expect ${pkgs.writeText "create-navidrome-user.expect" ''
            set timeout 30
            set command [list navidrome --configfile ${navidromeConfig} user create --username $env(MUSIC_DISCOVERY_USERNAME)]
            if {$env(MUSIC_DISCOVERY_ROLE) eq "admin"} {
              lappend command --admin
            }
            spawn -noecho {*}$command
            expect "Enter new password*"
            send -- "$env(MUSIC_DISCOVERY_PASSWORD)\r"
            expect "Confirm new password*"
            send -- "$env(MUSIC_DISCOVERY_PASSWORD)\r"
            expect eof
            catch wait result
            exit [lindex $result 3]
          ''}
      }

      if ! has_user admin; then
        create_user admin "$NAVIDROME_ADMIN_PASSWORD" admin
        users_json="$(navidrome --configfile ${navidromeConfig} user list --format json)"
      fi
      if ! has_user audiomuse; then
        create_user audiomuse "$NAVIDROME_SERVICE_PASSWORD" regular
      fi

      # The plugin runs inside Navidrome, so loopback reaches the only
      # published AudioMuse port. Its bearer token never enters the Nix store.
      api_token="$(cat "$CREDENTIALS_DIRECTORY/audiomuse-api-token")"
      plugin_config="$RUNTIME_DIRECTORY/audiomuse-plugin.json"
      jq --null-input \
        --arg apiUrl "http://127.0.0.1:${toString audioMusePort}" \
        --arg apiToken "$api_token" \
        '{
          apiUrl: $apiUrl,
          apiToken: $apiToken,
          artistSimilarCount: 20,
          instantMixSource: "similarSong",
          eliminateDuplicates: true,
          radiusSimilarity: true
        }' >"$plugin_config"
      navidrome --configfile ${navidromeConfig} plugin rescan
      navidrome --configfile ${navidromeConfig} plugin edit audiomuseai \
        --config-file "$plugin_config" --users audiomuse --all-libraries --no-write-access
      if [ -r ${lib.escapeShellArg audioMuseHouseholdApproval} ]; then
        navidrome --configfile ${navidromeConfig} plugin edit audiomuseai \
          --all-users --all-libraries --no-write-access
        navidrome --configfile ${navidromeConfig} plugin enable audiomuseai
      else
        navidrome --configfile ${navidromeConfig} plugin disable audiomuseai
        echo "AudioMuse plugin remains disabled pending household isolation approval"
      fi
      rm -f "$plugin_config"
    '';
  };
in
{
  # These dotenv bundles are generated and encrypted during repository
  # provisioning. Each consumer receives only the credentials it needs.
  nixSeal.secrets = {
    music-discovery-audiomuse-settings = {
      owner = "root";
      group = "root";
      mode = "0400";
      phase = "services";
      restartUnits = [
        "audiomuse-ai.service"
        "music-discovery-bootstrap-credential.service"
      ];
    };
    music-discovery-navidrome-settings = {
      owner = "root";
      group = "root";
      mode = "0400";
      phase = "services";
      restartUnits = [ "music-discovery-bootstrap.service" ];
    };
  };

  services.navidrome = {
    enable = true;
    plugins = with pkgs.navidromePlugins; [
      audiomuseai
      listenbrainz-daily-playlist
    ];
    settings = navidromeSettings;
  };
  services.audiomuse-ai = {
    enable = true;
    environmentFile = audioMuseEnvironment;
    extraEnvironment = {
      TZ = config.time.timeZone;
      # The setup bootstrap creates this local account before AudioMuse starts.
      NAVIDROME_URL = "http://127.0.0.1:${toString navidromePort}";
      MEDIASERVER_TYPE = "navidrome";
    };
  };

  # Both native applications use loopback. Physical LAN clients use Caddy's
  # encrypted endpoint instead.
  services.caddy = {
    enable = true;
    virtualHosts."https://${config.networking.hostName}:${toString listenerPort}" = {
      serverAliases = [ "https://${listenerIPv4}:${toString listenerPort}" ];
      # Some Subsonic clients put authentication fields in request URLs.
      logFormat = null;
      extraConfig = ''
        tls internal
        header -Server
        reverse_proxy 127.0.0.1:${toString navidromePort}
      '';
    };
  };

  # Upstream's tmpfiles rule would create the library during early boot even
  # when /srv/data is absent. Prepare all writable paths only after systemd has
  # verified the encrypted data mount.
  systemd.tmpfiles.settings.navidromeDirs.${musicFolder} = lib.mkForce { };
  systemd.services.music-discovery-directories = {
    description = "Prepare music-discovery directories on the encrypted data volume";
    before = [ "navidrome.service" ];
    unitConfig = {
      ConditionPathIsMountPoint = "/srv/data";
      RequiresMountsFor = [ "/srv/data" ];
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "5s";
      ExecStart = pkgs.writeShellScript "prepare-music-discovery-directories" ''
        set -eu
        ${pkgs.coreutils}/bin/install -d -m 2775 -o root -g users ${lib.escapeShellArg musicFolder}
        ${pkgs.coreutils}/bin/install -d -m 0711 -o root -g root ${lib.escapeShellArg backupRoot}
        ${pkgs.coreutils}/bin/install -d -m 0700 -o navidrome -g navidrome ${lib.escapeShellArg "${backupRoot}/navidrome"}
        ${pkgs.coreutils}/bin/install -d -m 0700 -o audiomuse -g audiomuse ${lib.escapeShellArg "${backupRoot}/audiomuse"}
      '';
    };
  };
  users.users = {
    navidrome.extraGroups = [ "users" ];
  };
  systemd.services.navidrome = {
    requires = [
      "music-discovery-directories.service"
      "nix-seal-activate.service"
    ];
    after = [
      "music-discovery-directories.service"
      "nix-seal-activate.service"
    ];
    unitConfig = {
      ConditionPathIsMountPoint = "/srv/data";
      RequiresMountsFor = [
        musicFolder
        backupRoot
      ];
    };
    serviceConfig.ReadOnlyPaths = [ musicFolder ];
    # Version 0.64.0 rewrites every internal ID on first start. Keep a one-time
    # SQLite backup outside Navidrome's normal rotation before that migration.
    serviceConfig.ExecStartPre = pkgs.writeShellScript "backup-navidrome-before-0.64" ''
      set -eu
      database=/var/lib/navidrome/navidrome.db
      backup=${lib.escapeShellArg "${backupRoot}/navidrome/pre-0.64.0.db"}
      if [ -f "$database" ] && [ ! -e "$backup" ]; then
        partial="$backup.partial"
        trap '${pkgs.coreutils}/bin/rm -f "$partial"' EXIT
        ${pkgs.sqlite}/bin/sqlite3 "$database" ".backup '$partial'"
        ${pkgs.coreutils}/bin/mv "$partial" "$backup"
        trap - EXIT
      fi
    '';
  };

  systemd.services.music-discovery-bootstrap-credential = {
    description = "Project the AudioMuse API token for Navidrome bootstrap";
    requires = [ "nix-seal-activate.service" ];
    after = [ "nix-seal-activate.service" ];
    before = [ "music-discovery-bootstrap.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "root";
      Group = "root";
      UMask = "0077";
      RuntimeDirectory = "music-discovery-bootstrap-credential";
      RuntimeDirectoryMode = "0700";
      EnvironmentFile = audioMuseEnvironment;
      ExecStart = pkgs.writeShellScript "project-audiomuse-api-token" ''
        set -eu
        target=${lib.escapeShellArg bootstrapAudioMuseCredential}
        partial="$target.partial"
        trap '${pkgs.coreutils}/bin/rm -f "$partial"' EXIT
        ${pkgs.coreutils}/bin/printf %s "$API_TOKEN" >"$partial"
        ${pkgs.coreutils}/bin/chmod 0400 "$partial"
        ${pkgs.coreutils}/bin/mv "$partial" "$target"
        trap - EXIT
      '';
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
    };
  };

  systemd.services.music-discovery-bootstrap = {
    description = "Provision Navidrome discovery accounts and the AudioMuse plugin";
    wantedBy = [ "multi-user.target" ];
    requires = [
      "music-discovery-bootstrap-credential.service"
      "navidrome.service"
      "nix-seal-activate.service"
    ];
    after = [
      "music-discovery-bootstrap-credential.service"
      "navidrome.service"
      "nix-seal-activate.service"
    ];
    partOf = [ "music-discovery-bootstrap-credential.service" ];
    unitConfig.ConditionPathIsMountPoint = "/srv/data";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "navidrome";
      Group = "navidrome";
      RuntimeDirectory = "music-discovery-bootstrap";
      UMask = "0077";
      EnvironmentFile = [ navidromeEnvironment ];
      LoadCredential = [ "audiomuse-api-token:${bootstrapAudioMuseCredential}" ];
      ExecStart = "${bootstrap}/bin/music-discovery-bootstrap";
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };
  systemd.services.audiomuse-ai = {
    requires = [
      "music-discovery-bootstrap.service"
      "nix-seal-activate.service"
    ];
    after = [
      "music-discovery-bootstrap.service"
      "nix-seal-activate.service"
    ];
    unitConfig.ConditionPathIsMountPoint = "/srv/data";
  };

  systemd.services.audiomuse-backup = {
    description = "Back up and prune the AudioMuse PostgreSQL database";
    requires = [ "postgresql.service" ];
    after = [ "postgresql.service" ];
    unitConfig = {
      ConditionPathIsMountPoint = "/srv/data";
      RequiresMountsFor = [ "${backupRoot}/audiomuse" ];
    };
    serviceConfig = {
      Type = "oneshot";
      User = "audiomuse";
      Group = "audiomuse";
      UMask = "0077";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ "${backupRoot}/audiomuse" ];
    };
    script = ''
      set -eu
      stamp="$(${pkgs.coreutils}/bin/date --utc +%Y%m%dT%H%M%SZ)"
      ready=0
      for _ in $(${pkgs.coreutils}/bin/seq 1 60); do
        if ${config.services.postgresql.package}/bin/pg_isready \
          --host /run/postgresql --username audiomusedb --dbname audiomusedb --quiet; then
          ready=1
          break
        fi
        ${pkgs.coreutils}/bin/sleep 1
      done
      if [ "$ready" -ne 1 ]; then
        echo "AudioMuse PostgreSQL did not become ready within 60 seconds" >&2
        exit 1
      fi

      partial=${lib.escapeShellArg "${backupRoot}/audiomuse"}/audiomuse-$stamp.dump.partial
      cleanup() {
        ${pkgs.coreutils}/bin/rm -f "$partial"
      }
      trap cleanup EXIT
      ${config.services.postgresql.package}/bin/pg_dump \
        --host /run/postgresql --username audiomusedb --format custom \
        --file "$partial" audiomusedb
      ${pkgs.coreutils}/bin/mv "$partial" "''${partial%.partial}"
      trap - EXIT
      ${pkgs.findutils}/bin/find ${lib.escapeShellArg "${backupRoot}/audiomuse"} \
        -type f -name 'audiomuse-*.dump' -mtime +14 -delete
    '';
  };
  systemd.timers.audiomuse-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 04:30:00";
      Persistent = true;
      RandomizedDelaySec = "15m";
    };
  };

  # Caddy's encrypted endpoint is limited to directly connected private
  # networks. AudioMuse and Navidrome keep their cleartext listeners on
  # loopback.
  networking.firewall.extraInputRules = lib.mkAfter ''
    iifname { "en*", "eth*", "wl*" } ip saddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } tcp dport ${toString listenerPort} accept comment "allow Navidrome HTTPS from private IPv4 LANs"
    iifname { "en*", "eth*", "wl*" } ip6 saddr fc00::/7 tcp dport ${toString listenerPort} accept comment "allow Navidrome HTTPS from IPv6 ULA networks"
  '';
}
