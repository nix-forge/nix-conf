{
  config,
  lib,
  pkgs,
  ...
}:
let
  network = builtins.fromJSON (builtins.readFile ../../../../../shared/local/network.json);
  mediaMounts = config.homelab.storage.requiredMounts;
  musicFolder = "${config.homelab.storage.libraryDir}/music";
  musicDiscoveryRoot = "${config.homelab.storage.rootDir}/.services/music-discovery";
  backupRoot = "${musicDiscoveryRoot}/backups";
  prepareDirectories = pkgs.writeShellApplication {
    name = "prepare-music-discovery-directories";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ./scripts/prepare-music-discovery-directories.sh;
  };
  resolvePluginUserIds = pkgs.writeShellApplication {
    name = "resolve-navidrome-plugin-user-ids";
    runtimeInputs = [ pkgs.jq ];
    text = builtins.readFile ./scripts/resolve-navidrome-plugin-user-ids.sh;
  };
  navidromePort = 4533;
  listenerPort = 4534;
  listenerIPv4 = network.desktopTrustedAddress;
  audioMusePort = 8000;
  lyricModels = "${config.services.audiomuse-ai.package.models}/model";
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
    # Canonical sidecars are shared with Jellyfin; embedded edition art is a fallback.
    CoverArtPriority = "cover.*, folder.*, front.*, embedded, external";
    CoverArtQuality = 90;
    # Feishin asks Navidrome for the playing track's art. Imported files can
    # embed low-quality edition packaging even when the album has a clean cover.
    # Use the album's curated artwork for tracks and across multi-disc albums.
    EnableMediaFileCoverArt = false;
    DiscArtPriority = "";
    # Curated sidecars win. Imported files can carry spam in embedded lyric
    # tags, so try the multi-source plugin before embedded and plain text.
    LyricsPriority = ".ttml,.yaml,.yml,.elrc,.lrc,.srt,nd-lyrics,embedded,.txt";
    Scanner.Schedule = "@every 5m";
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
  # the plugin directory from services.navidrome.withPlugins.
  navidromeConfig =
    (pkgs.formats.json { }).generate "navidrome.json"
      config.services.navidrome.settings;
  lyricsPluginConfig = (pkgs.formats.json { }).generate "nd-lyrics.json" {
    lyricsFormats = "ttml,elrc,lyricsfile,lrc,srt,plain";
    providerMode = "sync";
    preferUncensored = true;
    durationToleranceSeconds = 3;
    requireAlbumMatch = false;
    writeLyrics = false;
    # A transient provider miss should be retried sooner than a good synced
    # match. The plugin's default negative cache keeps misses for 24 hours.
    negativeCacheTtlHours = 2;
    perTypeCacheTtl = true;
    providersList =
      map
        (provider: {
          inherit provider;
          romanizationScript = "none";
          translationLanguage = "none";
        })
        [
          "lrclib"
          "binilyrics"
          "qqmusic"
          "netease"
          "kugou"
          "lrcmux"
          "lyrics.ovh"
        ];
  };
  configureLyricsPlugin =
    pkgs.writers.writePython3 "configure-lyrics-plugin"
      {
        flakeIgnore = [
          "E501"
          "W503"
        ];
      }
      (
        (import ../../../../../../lib/templates/text.nix) ./scripts/configure_lyrics_plugin.py {
          toString_navidromePort = toString navidromePort;
        }
      );
  linkListenBrainz =
    pkgs.writers.writePython3 "link-listenbrainz"
      {
        flakeIgnore = [
          "E501"
          "W503"
        ];
      }
      (
        (import ../../../../../../lib/templates/text.nix) ./scripts/link_listenbrainz.py {
          toString_navidromePort = toString navidromePort;
        }
      );
  bootstrap = pkgs.writeShellApplication {
    name = "music-discovery-bootstrap";
    runtimeInputs = [
      config.services.navidrome.finalPackage
      pkgs.coreutils
      pkgs.curl
      pkgs.expect
      pkgs.jq
    ];
    text = (import ../../../../../../lib/templates/text.nix) ./scripts/music-discovery-bootstrap.sh {
      toString_navidromePort = toString navidromePort;
      inherit navidromeConfig;
      pkgs_writeText_create_navidrome_user_expect_set_timeout_30_l =
        pkgs.writeText "create-navidrome-user.expect"
          (
            (import ../../../../../../lib/templates/text.nix) ./scripts/create-navidrome-user.exp {
              inherit navidromeConfig;
            }
          );
      lib_getExe_resolvePluginUserIds = lib.getExe resolvePluginUserIds;
      inherit linkListenBrainz;
      inherit configureLyricsPlugin;
      inherit lyricsPluginConfig;
      toString_audioMusePort = toString audioMusePort;
      lib_escapeShellArg_audioMuseHouseholdApproval = lib.escapeShellArg audioMuseHouseholdApproval;
    };
  };
in
{
  # These dotenv bundles are generated and encrypted during repository
  # provisioning. Each consumer receives only the credentials it needs.
  nixSeal.secrets = {
    music-discovery-listener-password = {
      owner = "root";
      group = "root";
      mode = "0400";
      phase = "services";
      restartUnits = [ "music-discovery-bootstrap.service" ];
    };
    music-discovery-listenbrainz-identity = {
      owner = "root";
      group = "root";
      mode = "0400";
      phase = "services";
      restartUnits = [ "music-discovery-bootstrap.service" ];
    };
    feishin-listener-password = {
      owner = "root";
      group = "root";
      mode = "0400";
      phase = "services";
      restartUnits = [ "music-discovery-bootstrap.service" ];
    };
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
    withPlugins = plugins: [
      pkgs.navidrome-plugin-audiomuseai-personal
      plugins.listenbrainz-daily-playlist
      plugins.lyrics-plugin
    ];
    settings = navidromeSettings;
  };
  # Retain this deployment's existing database major version during extraction.
  services.postgresql.package = pkgs.postgresql_15;
  services.audiomuse-ai = {
    enable = true;
    environmentFile = audioMuseEnvironment;
    extraEnvironment = {
      TZ = config.time.timeZone;
      # The setup bootstrap creates this local account before AudioMuse starts.
      NAVIDROME_URL = "http://127.0.0.1:${toString navidromePort}";
      MEDIASERVER_TYPE = "navidrome";
      # The native lyric loaders have separate Docker-path defaults.
      LYRICS_GTE_ONNX_PATH = "${lyricModels}/gte-multilingual-base-int8.onnx";
      LYRICS_GTE_TOKENIZER_DIR = "${lyricModels}/gte-multilingual-base";
      SILERO_VAD_ONNX_PATH = "${lyricModels}/silero_vad.onnx";
    };
  };

  # Existing Subsonic clients still use this internal-CA endpoint on port
  # 4534. New clients use the shared LAN HTTPS ingress on port 443. Retire
  # this listener after saved client URLs and trust stores are migrated.
  services.caddy = {
    enable = true;
    virtualHosts."https://${config.networking.hostName}:${toString listenerPort}" = {
      serverAliases = [ "https://${listenerIPv4}:${toString listenerPort}" ];
      # Some Subsonic clients put authentication fields in request URLs.
      logFormat = null;
      extraConfig = ''
        bind ${listenerIPv4}
        tls internal
        header -Server
        reverse_proxy 127.0.0.1:${toString navidromePort}
      '';
    };
  };

  # Retire only this host's marked runtime mount repair once Nix supplies the
  # corrected units. Runtime unit definitions otherwise outrank /etc units.
  system.activationScripts.music-storage-mount-repair-cleanup = {
    deps = [ "etc" ];
    text = builtins.readFile ./scripts/remove-stale-mount-repairs.sh;
  };

  # Upstream's tmpfiles rule would create the library during early boot even
  # when the media volume is absent. Prepare all writable paths only after systemd has
  # verified the configured media mounts.
  systemd.tmpfiles.settings.navidromeDirs.${musicFolder} = lib.mkForce { };
  systemd.services.music-discovery-directories = {
    description = "Prepare music-discovery directories on the media volume";
    before = [ "navidrome.service" ];
    requires = [ "homelab-storage.service" ];
    after = [ "homelab-storage.service" ];
    unitConfig = {
      ConditionPathIsMountPoint = mediaMounts;
      RequiresMountsFor = mediaMounts ++ [ config.homelab.storage.rootDir ];
    };
    serviceConfig = {
      Type = "oneshot";
      Restart = "on-failure";
      RestartSec = "5s";
      ExecStart = "${lib.getExe prepareDirectories} ${
        lib.escapeShellArgs [
          config.homelab.storage.rootDir
          musicFolder
          config.homelab.storage.group
          "root"
          "root"
          "navidrome"
          "navidrome"
          "audiomuse"
          "audiomuse"
        ]
      }";
    };
  };
  users.users = {
    navidrome.extraGroups = [ config.homelab.storage.group ];
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
      ConditionPathIsMountPoint = mediaMounts;
      RequiresMountsFor = [
        musicFolder
        backupRoot
      ];
    };
    serviceConfig.ReadOnlyPaths = [ musicFolder ];
    # Version 0.64.0 rewrites every internal ID on first start. Keep a one-time
    # SQLite backup outside Navidrome's normal rotation before that migration.
    serviceConfig.ExecStartPre = pkgs.writeShellScript "backup-navidrome-before-0.64" (
      (import ../../../../../../lib/templates/text.nix) ./scripts/backup-navidrome-before-0-64.sh {
        lib_escapeShellArg_backupRoot_navidrome_pre_0_64_0_db = lib.escapeShellArg "${backupRoot}/navidrome/pre-0.64.0.db";
        pkgs_coreutils = pkgs.coreutils;
        pkgs_sqlite = pkgs.sqlite;
      }
    );
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
      ExecStart = pkgs.writeShellScript "project-audiomuse-api-token" (
        (import ../../../../../../lib/templates/text.nix) ./scripts/project-audiomuse-api-token.sh {
          lib_escapeShellArg_bootstrapAudioMuseCredential = lib.escapeShellArg bootstrapAudioMuseCredential;
          pkgs_coreutils = pkgs.coreutils;
        }
      );
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
    unitConfig.ConditionPathIsMountPoint = mediaMounts;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "navidrome";
      Group = "navidrome";
      RuntimeDirectory = "music-discovery-bootstrap";
      UMask = "0077";
      EnvironmentFile = [ navidromeEnvironment ];
      LoadCredential = [
        "navidrome-admin-username:${config.nixSeal.secrets.homelab-navidrome-admin-username.path}"
        "navidrome-service-username:${config.nixSeal.secrets.homelab-navidrome-service-username.path}"
        "feishin-listener-username:${config.nixSeal.secrets.homelab-navidrome-listener-username.path}"
        "audiomuse-api-token:${bootstrapAudioMuseCredential}"
        "feishin-listener-password:${config.nixSeal.secrets.feishin-listener-password.path}"
        "listenbrainz-identity:${config.nixSeal.secrets.music-discovery-listenbrainz-identity.path}"
        "listenbrainz-listener-password:${config.nixSeal.secrets.music-discovery-listener-password.path}"
      ];
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
    unitConfig.ConditionPathIsMountPoint = mediaMounts;
  };

  systemd.services.audiomuse-server-configuration = {
    description = "Reconcile AudioMuse's persisted Navidrome endpoint";
    wantedBy = [ "multi-user.target" ];
    requires = [
      "audiomuse-ai.service"
      "music-discovery-bootstrap-credential.service"
    ];
    after = [
      "audiomuse-ai.service"
      "music-discovery-bootstrap-credential.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "audiomuse";
      Group = "audiomuse";
      LoadCredential = [ "api-token:${bootstrapAudioMuseCredential}" ];
      ExecStart = "${
        pkgs.writers.writePython3 "configure-audiomuse" {
          flakeIgnore = [
            "E501"
            "W503"
          ];
        } (builtins.readFile ./scripts/configure_audiomuse.py)
      } http://127.0.0.1:${toString navidromePort}";
      Restart = "on-failure";
      RestartSec = "10s";
      TimeoutStartSec = "2min";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      IPAddressDeny = [ "any" ];
      IPAddressAllow = [ "localhost" ];
    };
  };

  systemd.services.audiomuse-backup = {
    description = "Back up and prune the AudioMuse PostgreSQL database";
    requires = [
      "postgresql.service"
      "music-discovery-directories.service"
    ];
    after = [
      "postgresql.service"
      "music-discovery-directories.service"
    ];
    unitConfig = {
      ConditionPathIsMountPoint = mediaMounts;
      RequiresMountsFor = [ "${backupRoot}/audiomuse" ];
    };
    serviceConfig = {
      Type = "oneshot";
      User = "audiomuse";
      Group = "audiomuse";
      # The media root is group-traversable; only this backup unit needs access.
      SupplementaryGroups = [ config.homelab.storage.group ];
      UMask = "0077";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ "${backupRoot}/audiomuse" ];
    };
    script = (import ../../../../../../lib/templates/text.nix) ./scripts/audiomuse-backup-script.sh {
      pkgs_coreutils = pkgs.coreutils;
      lib_escapeShellArg_backupRoot_audiomuse = lib.escapeShellArg "${backupRoot}/audiomuse";
      config_services_postgresql_package = config.services.postgresql.package;
      pkgs_findutils = pkgs.findutils;
    };
  };
  systemd.timers.audiomuse-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 04:30:00";
      Persistent = true;
      RandomizedDelaySec = "15m";
    };
  };

  # Keep the dedicated HTTPS listener on the household IPv4 LAN. AudioMuse
  # and Navidrome keep their cleartext listeners on loopback.
  networking.firewall.extraInputRules = lib.mkAfter ''
    iifname { "en*", "eth*", "wl*" } ip saddr ${network.trustedLanCIDR} tcp dport ${toString listenerPort} accept comment "allow Navidrome HTTPS from household IPv4 LAN"
  '';
}
