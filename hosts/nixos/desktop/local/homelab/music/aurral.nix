{
  config,
  lib,
  myLib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.desktopAurral;
  httpPort = toString cfg.httpPort;
  writeShellApplication = myLib.writers.writeShellApplication { inherit pkgs; };
  qualityPolicy = (pkgs.formats.json { }).generate "aurral-quality-policy.json" (
    cfg.qualityProfile // { inherit (cfg) onboarding slskd; }
  );
  mediaMounts = config.homelab.storage.requiredMounts;
  inherit (config.homelab.desktopMusic) libraryDir;
  # Aurral uses the shared music folder as its destination. Soulseek's
  # acquisition directory and Aurral's mutable service state are separate.
  downloadFolder = libraryDir;
  mediaGroup = config.homelab.storage.group;
  namespace = config.homelab.vpn.namespace.name;
  lidarrPort = toString config.services.lidarr.settings.server.port;
  musicTools = (import ../../../../../../flake/runtime-packages.nix { inherit pkgs; }).musicApiTools;
  rescan = lib.getExe' musicTools "rescan-shared-music-library";
  # Lidarr provides no readiness notification. Curl bounds safe GET retries;
  # the owning oneshot also caps the complete startup operation.
  waitForLidarr = writeShellApplication {
    name = "wait-for-lidarr";
    text =
      myLib.templates.renderText
        {
          name = "wait-for-lidarr.sh";
          text = ''
            # shellcheck shell=bash
            key="$(@cat@ "$CREDENTIALS_DIRECTORY/lidarr-api-key")"
            case "$key" in
            "" | *$'\n'* | *$'\r'*)
              echo "Invalid Lidarr API credential" >&2
              exit 1
              ;;
            esac
            printf 'X-Api-Key: %s\n' "$key" | @curl@
          '';
        }
        {
          cat = lib.getExe' pkgs.coreutils "cat";
          curl = lib.escapeShellArgs [
            (lib.getExe pkgs.curl)
            "--silent"
            "--show-error"
            "--fail"
            "--noproxy"
            "*"
            "--output"
            "/dev/null"
            "--max-time"
            "10"
            "--retry"
            "10"
            "--retry-connrefused"
            "--retry-max-time"
            "60"
            "--header"
            "@-"
            "http://127.0.0.1:${lidarrPort}/api/v1/system/status"
          ];
        };
  };
  bootstrap =
    lib.getExe
      (import ../../../../../../flake/runtime-packages.nix { inherit pkgs; }).aurralBootstrap;
in
{
  users.groups.aurral = { };
  users.users.aurral = {
    isSystemUser = true;
    group = "aurral";
    extraGroups = [
      mediaGroup
      "slskd"
    ];
    home = "/var/lib/aurral";
  };

  systemd.timers.aurral-library-rescan = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "5min";
    };
  };
  systemd.services.aurral-library-rescan = {
    description = "Index shared music files in Lidarr";
    requires = [ "lidarr.service" ];
    after = [ "lidarr.service" ];
    environment = {
      LIDARR_URL = "http://127.0.0.1:${lidarrPort}";
      MUSIC_ROOT = libraryDir;
      CURL = lib.getExe pkgs.curl;
      HTTP_TIMEOUT_SECONDS = "10";
      HTTP_RETRY_BUDGET_SECONDS = "60";
      HTTP_RETRY_ATTEMPTS = "10";
    };
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "120s";
      User = "aurral";
      Group = "aurral";
      ExecStart = rescan;
      LoadCredential = [ "lidarr-api-key:${config.nixSeal.secrets.homelab-lidarr-api-key.path}" ];
      NoNewPrivileges = true;
      CapabilityBoundingSet = "";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      RestrictNamespaces = true;
      RestrictAddressFamilies = [ "AF_INET" ];
      IPAddressDeny = [ "any" ];
      IPAddressAllow = [ "127.0.0.0/8" ];
      MemoryMax = "128M";
      TasksMax = 16;
    };
  };

  systemd.services.aurral-directories = {
    description = "Prepare Aurral's music directory on the media volume";
    before = [ "aurral.service" ];
    requires = [ "homelab-storage.service" ];
    after = [ "homelab-storage.service" ];
    unitConfig.RequiresMountsFor = mediaMounts ++ [ libraryDir ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.coreutils}/bin/install -d -m 2770 -o lidarr -g ${mediaGroup} ${lib.escapeShellArg downloadFolder}";
    };
  };

  systemd.services.aurral = {
    description = "Aurral music discovery and requests";
    wantedBy = [ "multi-user.target" ];
    requires = [
      "aurral-directories.service"
      "aurral-lidarr-vpn.service"
    ];
    after = [
      "aurral-directories.service"
      "aurral-lidarr-vpn.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    vpn = {
      enable = true;
      inherit namespace;
      extraAddressFamilies = [ "AF_UNIX" ];
    };
    unitConfig.RequiresMountsFor = mediaMounts ++ [ libraryDir ];
    environment = {
      AURRAL_QUALITY_POLICY = toString qualityPolicy;
      AURRAL_DATA_DIR = "/var/lib/aurral";
      AURRAL_HOST = "127.0.0.1";
      PORT = httpPort;
      DOWNLOAD_FOLDER = downloadFolder;
      # Only the local reverse proxy may supply client IP headers.
      TRUST_PROXY = "loopback";
      AURRAL_PUBLIC_URL = "https://aurral.${config.homelab.operations.lanHttps.domain}";
      APP_VERSION = pkgs.aurral.version;
      SESSION_EXPIRY_HOURS = "72";
      TZ = config.time.timeZone;
    };
    serviceConfig = {
      Type = "simple";
      User = "aurral";
      Group = "aurral";
      SupplementaryGroups = [
        mediaGroup
        "slskd"
      ];
      ExecStart = lib.getExe pkgs.aurral;
      WorkingDirectory = "${pkgs.aurral}/lib/aurral";
      StateDirectory = "aurral";
      StateDirectoryMode = "0700";
      UMask = "0007";
      Restart = "on-failure";
      RestartSec = "5s";
      TimeoutStopSec = "20s";
      MemoryMax = "2G";
      TasksMax = 512;
      NoNewPrivileges = true;
      CapabilityBoundingSet = "";
      AmbientCapabilities = [ ];
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ProtectControlGroups = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectClock = true;
      ProtectProc = "invisible";
      RestrictSUIDSGID = true;
      RestrictNamespaces = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
      SystemCallArchitectures = "native";
      ReadWritePaths = [
        downloadFolder
        config.homelab.apps.slskd.downloadsDir
      ];
      IPAddressDeny = [
        "0.0.0.0/8"
        "10.0.0.0/8"
        "100.64.0.0/10"
        "172.16.0.0/12"
        "192.168.0.0/16"
        "169.254.0.0/16"
        "198.18.0.0/15"
        "224.0.0.0/4"
        "240.0.0.0/4"
        "fc00::/7"
        "fe80::/10"
        "ff00::/8"
      ];
      IPAddressAllow = [
        "127.0.0.0/8"
        "::1/128"
        "${config.homelab.vpn.namespace.bindAddress}/32"
      ]
      ++ map (
        address: "${address}/${if lib.hasInfix ":" address then "128" else "32"}"
      ) config.homelab.vpn.interface.dns;
    };
  };

  # Remove only the owned emergency package override after declarative activation.
  system.activationScripts.aurral-artist-identity-repair-cleanup.text = myLib.templates.renderText {
    name = "aurral-artist-identity-repair-cleanup-text.sh";
    text = ''
      # shellcheck shell=bash
      aurral_repair_override=/etc/systemd/system.control/aurral.service.d/96-artist-identity.conf
      if [[ -f $aurral_repair_override && ! -L $aurral_repair_override ]]; then
        IFS= read -r aurral_repair_header <"$aurral_repair_override" || true
        if [[ $aurral_repair_header == '# Temporary Aurral artist identity repair.' ]]; then
          @pkgs_coreutils@/bin/rm -- "$aurral_repair_override"
        fi
      fi
    '';
  } { pkgs_coreutils = pkgs.coreutils; };

  system.activationScripts.aurral-request-quality-repair-cleanup.text = myLib.templates.renderText {
    name = "aurral-request-quality-repair-cleanup-text.sh";
    text = ''
      # shellcheck shell=bash
      repair=/etc/systemd/system.control/aurral-bootstrap.service.d/97-request-quality.conf
      if [[ -f $repair && ! -L $repair ]]; then
        IFS= read -r header <"$repair" || true
        if [[ $header == '# Temporary Aurral request quality repair.' ]]; then
          @pkgs_coreutils@/bin/rm -- "$repair"
          @pkgs_coreutils@/bin/rm -f -- /nix/var/nix/gcroots/aurral-request-quality-repair
        fi
      fi
    '';
  } { pkgs_coreutils = pkgs.coreutils; };

  systemd.services.aurral-quality-profile = {
    description = "Prepare the managed music quality profile before Lidarr integration";
    requires = [
      "lidarr.service"
      "nix-seal-activate.service"
    ];
    after = [
      "lidarr.service"
      "nix-seal-activate.service"
    ];
    environment = {
      AURRAL_QUALITY_ONLY = "1";
      AURRAL_URL = cfg.backendUrl;
      LIDARR_URL = "http://127.0.0.1:${lidarrPort}";
      SLSKD_URL = "unused";
      AURRAL_QUALITY_POLICY = toString qualityPolicy;
      AURRAL_DATA_DIR = "/var/lib/aurral";
    };
    serviceConfig = {
      Type = "oneshot";
      User = "aurral";
      Group = "aurral";
      ExecStartPre = lib.getExe waitForLidarr;
      TimeoutStartSec = "180s";
      ExecStart = "${bootstrap} ${lib.escapeShellArg downloadFolder} ${lib.escapeShellArg libraryDir}";
      LoadCredential = [ "lidarr-api-key:${config.nixSeal.secrets.homelab-lidarr-api-key.path}" ];
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      IPAddressDeny = [ "any" ];
      IPAddressAllow = [ "127.0.0.0/8" ];
    };
  };
  systemd.services.homelab-integrate-lidarr = {
    requires = [ "aurral-quality-profile.service" ];
    after = [ "aurral-quality-profile.service" ];
  };

  systemd.services.aurral-listenbrainz-identity = {
    description = "Validate Aurral's ListenBrainz identity without changing an account";
    requires = [ "nix-seal-activate.service" ];
    after = [
      "nix-seal-activate.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    vpn = {
      enable = true;
      inherit namespace;
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "30s";
      User = "aurral";
      Group = "aurral";
      RuntimeDirectory = "aurral-listenbrainz-identity";
      RuntimeDirectoryMode = "0700";
      UMask = "0077";
      LoadCredential = [
        "listenbrainz-identity:${config.nixSeal.secrets.music-discovery-listenbrainz-identity.path}"
      ];
      ExecStart = "${lib.getExe' musicTools "verify-listenbrainz-identity"} /run/aurral-listenbrainz-identity/validated.json";
      TimeoutStartSec = "30s";
      NoNewPrivileges = true;
      CapabilityBoundingSet = "";
      AmbientCapabilities = "";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
    };
  };

  systemd.services.aurral-bootstrap = {
    description = "Configure Aurral with Lidarr and ListenBrainz history";
    wantedBy = [ "multi-user.target" ];
    # A failed provider lookup must not prevent the bootstrap process from
    # starting and retrying while identity validation recovers independently.
    wants = [ "aurral-listenbrainz-identity.service" ];
    requires = [
      "aurral.service"
      "aurral-http-host.service"
      "aurral-quality-profile.service"
      "lidarr.service"
      "nix-seal-activate.service"
    ];
    after = [
      "aurral-listenbrainz-identity.service"
      "aurral.service"
      "aurral-http-host.service"
      "aurral-quality-profile.service"
      "lidarr.service"
      "nix-seal-activate.service"
    ];
    environment = {
      LISTENBRAINZ_IDENTITY_RECEIPT = "/run/aurral-listenbrainz-identity/validated.json";
      AURRAL_LIDARR_WEBHOOK = "1";
      AURRAL_URL = cfg.backendUrl;
      LIDARR_URL = "http://127.0.0.1:${lidarrPort}";
      SLSKD_URL = "http://${config.homelab.vpn.namespace.bindAddress}:${toString config.homelab.apps.slskd.webPort}";
      AURRAL_QUALITY_POLICY = toString qualityPolicy;
      AURRAL_DATA_DIR = "/var/lib/aurral";
    };
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Group = "root";
      UMask = "0077";
      Restart = "on-failure";
      RestartSec = "30s";
      LoadCredential = [
        "aurral-admin-username:${config.nixSeal.secrets.homelab-aurral-admin-username.path}"
        "aurral-admin-password:${config.nixSeal.secrets.homelab-aurral-admin-password.path}"
        "lidarr-api-key:${config.nixSeal.secrets.homelab-lidarr-api-key.path}"
        "listenbrainz-identity:${config.nixSeal.secrets.music-discovery-listenbrainz-identity.path}"
        "slskd-settings:${config.nixSeal.secrets.music-discovery-slskd-settings.path}"
      ];
      ExecStartPre = "${lib.getExe pkgs.curl} --fail --silent --show-error --output /dev/null --retry 20 --retry-delay 2 --retry-connrefused --retry-all-errors --connect-timeout 2 --max-time 3 ${cfg.backendUrl}/api/health";
      ExecStart = "${bootstrap} ${lib.escapeShellArg downloadFolder} ${lib.escapeShellArg libraryDir}";
      NoNewPrivileges = true;
      CapabilityBoundingSet = [ ];
      AmbientCapabilities = [ ];
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
      IPAddressDeny = [ "any" ];
      IPAddressAllow = [
        "127.0.0.0/8"
        "::1/128"
      ];
      ReadWritePaths = [ "/var/lib/aurral" ];
    };
  };

  assertions = [
    {
      assertion =
        config.systemd.services.aurral.vpn.enable
        && config.systemd.services.aurral.vpn.namespace == namespace
        && config.systemd.services.aurral.serviceConfig.NetworkNamespacePath == "/run/netns/${namespace}";
      message = "Aurral must run in the homelab VPN namespace for acquisition and metadata privacy.";
    }
    {
      assertion =
        let
          identity = config.systemd.services.aurral-listenbrainz-identity;
          rescanService = config.systemd.services.aurral-library-rescan.serviceConfig;
        in
        identity.vpn.enable
        && identity.vpn.namespace == namespace
        && identity.serviceConfig.NetworkNamespacePath == "/run/netns/${namespace}"
        && rescanService.IPAddressDeny == [ "any" ]
        && rescanService.IPAddressAllow == [ "127.0.0.0/8" ];
      message = "Aurral identity lookup must use the VPN and Lidarr rescans must stay on loopback.";
    }
    {
      assertion =
        config.homelab.storage.enable
        && config.homelab.apps.lidarr.enable
        && config.homelab.apps.slskd.enable
        && config.services.navidrome.enable
        && config.services.navidrome.settings.MusicFolder == libraryDir
        && !(builtins.elem cfg.httpPort config.networking.firewall.allowedTCPPorts);
      message = "Aurral needs the homelab music services and Navidrome's music folder; its direct HTTP port must stay closed to the LAN.";
    }
  ];
}
