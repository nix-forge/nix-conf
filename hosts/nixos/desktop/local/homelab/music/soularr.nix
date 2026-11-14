{
  config,
  lib,
  pkgs,
  ...
}:
let
  downloadDir = config.homelab.apps.slskd.downloadsDir;
  settings = (pkgs.formats.ini { }).generate "soularr.ini" {
    Lidarr = {
      api_key = "@LIDARR_KEY@";
      host_url = "http://127.0.0.1:${toString config.services.lidarr.settings.server.port}";
      download_dir = downloadDir;
      disable_sync = false;
    };
    Slskd = {
      api_key = "@SLSKD_KEY@";
      host_url = "http://${config.homelab.vpn.namespace.bindAddress}:${toString config.homelab.apps.slskd.webPort}";
      url_base = "/";
      download_dir = downloadDir;
      delete_searches = true;
      stalled_timeout = 900;
      remote_queue_timeout = 180;
    };
    "Release Settings" = {
      use_selected_lidarr_release = true;
      use_most_common_tracknum = false;
      allow_multi_disc = true;
      accepted_countries = "Europe,Japan,United Kingdom,United States,[Worldwide],Australia,Canada";
      skip_region_check = false;
      accepted_formats = "CD,Digital Media";
    };
    "Search Settings" = {
      search_timeout = 30000;
      maximum_peer_queue = 25;
      minimum_peer_upload_speed = 0;
      minimum_filename_match_ratio = 0.8;
      minimum_search_interval = 5;
      allowed_filetypes = "flac,mp3 320,mp3 256";
      ignored_users = "";
      album_prepend_artist = true;
      search_type = "incrementing_page";
      number_of_albums_to_grab = 2;
      title_blacklist = "";
      search_blacklist = "";
      search_source = "missing";
      failed_import_denylist = true;
    };
    "Download Settings" = {
      download_filtering = true;
      use_extension_whitelist = false;
      extensions_whitelist = "";
    };
    Logging = {
      level = "INFO";
      log_to_file = false;
    };
  };
  prepare =
    pkgs.writers.writePython3 "soularr-runtime-config"
      {
        flakeIgnore = [
          "E501"
          "W503"
        ];
      }
      (
        (import ../../../../../../lib/templates/text.nix) ./scripts/soularr_runtime_config.py {
          inherit settings;
          LIDARR_KEY = null;
          SLSKD_KEY = null;
        }
      );
in
{
  # Remove only the targeted live units recorded by this deployment.
  system.activationScripts.music-integration-live-units-cleanup.text =
    (import ../../../../../../lib/templates/text.nix)
      ./scripts/music-integration-live-units-cleanup-text.sh
      { pkgs_coreutils = pkgs.coreutils; };
  systemd.services.soularr = {
    description = "Acquire missing Lidarr albums through Soulseek";
    requires = [
      "lidarr.service"
      "slskd.service"
      "soulseek-directories.service"
    ];
    after = [
      "lidarr.service"
      "slskd.service"
      "soulseek-directories.service"
      "aurral-bootstrap.service"
    ];
    unitConfig.RequiresMountsFor = [ downloadDir ];
    serviceConfig = {
      Type = "oneshot";
      User = "slskd";
      Group = "slskd";
      SupplementaryGroups = [ config.homelab.storage.group ];
      StateDirectory = "soularr";
      StateDirectoryMode = "0700";
      RuntimeDirectory = "soularr";
      RuntimeDirectoryMode = "0700";
      WorkingDirectory = "/var/lib/soularr";
      UMask = "0007";
      LoadCredential = [
        "lidarr-api-key:${config.nixSeal.secrets.homelab-lidarr-api-key.path}"
        "slskd-settings:${config.nixSeal.secrets.music-discovery-slskd-settings.path}"
      ];
      ExecStartPre = prepare;
      ExecStart = "${lib.getExe pkgs.soularr} --config-dir /run/soularr --var-dir /var/lib/soularr --no-lock-file";
      TimeoutStartSec = "45min";
      TimeoutStopSec = "30s";
      MemoryMax = "512M";
      TasksMax = 32;
      Nice = 10;
      IOSchedulingClass = "idle";
      NoNewPrivileges = true;
      CapabilityBoundingSet = "";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      RestrictNamespaces = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
      InaccessiblePaths = [ config.homelab.storage.libraryDir ];
      ReadWritePaths = [ downloadDir ];
      IPAddressDeny = [ "any" ];
      IPAddressAllow = [
        "127.0.0.0/8"
        "${config.homelab.vpn.namespace.bindAddress}/32"
      ];
    };
  };
  systemd.timers.soularr = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "10min";
      OnUnitInactiveSec = "15min";
      RandomizedDelaySec = "1min";
    };
  };
}
