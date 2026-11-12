{
  config,
  lib,
  pkgs,
  ...
}:
let
  qualityPolicy = (pkgs.formats.json { }).generate "aurral-quality-policy.json" (
    config.homelab.desktopAurral.qualityProfile
    // {
      inherit (config.homelab.desktopAurral) onboarding slskd;
    }
  );
  mediaMounts = config.homelab.storage.requiredMounts;
  musicFolder = "${config.homelab.storage.libraryDir}/music";
  downloadFolder = musicFolder;
  mediaGroup = config.homelab.storage.group;
  namespace = config.homelab.vpn.namespace.name;
  bridgeDirectory = "/run/aurral-network";
  lidarrPort = toString config.services.lidarr.settings.server.port;
  bridge = confined: command: {
    requires = [ "systemd-tmpfiles-setup.service" ];
    after = [ "systemd-tmpfiles-setup.service" ];
    vpn = lib.optionalAttrs confined {
      enable = true;
      inherit namespace;
      extraAddressFamilies = [ "AF_UNIX" ];
    };
    serviceConfig = {
      User = "aurral";
      Group = "aurral";
      ExecStart = "${lib.getExe pkgs.socat} ${command}";
      Restart = "on-failure";
      RestartSec = "2s";
      UMask = "0077";
      NoNewPrivileges = true;
      CapabilityBoundingSet = "";
      AmbientCapabilities = [ ];
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      RestrictNamespaces = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_UNIX"
      ];
      IPAddressDeny = [ "any" ];
      IPAddressAllow = [ "127.0.0.0/8" ];
      ReadWritePaths = [ bridgeDirectory ];
      TasksMax = 128;
      MemoryMax = "128M";
    };
  };
  rescan = pkgs.writers.writePython3 "rescan-shared-music-library" {
    libraries = [
      (import ../../../../../../lib/python/notification-process/package.nix { inherit pkgs; })
    ];
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } (builtins.readFile ./scripts/rescan_shared_music_library.py);
  # Lidarr provides no readiness notification. Curl bounds safe GET retries;
  # the owning oneshot also caps the complete startup operation.
  waitForLidarr = pkgs.writeShellApplication {
    name = "wait-for-lidarr";
    text = (import ../../../../../../lib/templates/text.nix) ./scripts/wait-for-lidarr.sh {
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
  bootstrap = pkgs.writers.writePython3 "bootstrap-aurral" {
    # The repository formats Python to 88 columns rather than pycodestyle's 79.
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } (builtins.readFile ./scripts/bootstrap_aurral.py);
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

  # Unix sockets preserve the existing loopback API URLs without granting the
  # VPN namespace a route into the host network. Every TCP bridge is local-only.
  systemd.tmpfiles.rules = [ "d ${bridgeDirectory} 0700 aurral aurral -" ];
  systemd.services.aurral-lidarr-host = bridge false "UNIX-LISTEN:${bridgeDirectory}/lidarr.sock,fork,unlink-early TCP:127.0.0.1:${lidarrPort}";
  systemd.services.aurral-lidarr-vpn =
    lib.recursiveUpdate
      (bridge true "TCP-LISTEN:${lidarrPort},bind=127.0.0.1,reuseaddr,fork UNIX-CONNECT:${bridgeDirectory}/lidarr.sock")
      {
        requires = [
          "systemd-tmpfiles-setup.service"
          "aurral-lidarr-host.service"
        ];
        after = [
          "systemd-tmpfiles-setup.service"
          "aurral-lidarr-host.service"
        ];
      };
  systemd.services.aurral-http-vpn =
    lib.recursiveUpdate
      (bridge true "UNIX-LISTEN:${bridgeDirectory}/http.sock,fork,unlink-early TCP:127.0.0.1:3001")
      {
        requires = [
          "systemd-tmpfiles-setup.service"
          "aurral.service"
        ];
        after = [
          "systemd-tmpfiles-setup.service"
          "aurral.service"
        ];
      };
  systemd.services.aurral-http-host =
    lib.recursiveUpdate
      (bridge false "TCP-LISTEN:3001,bind=127.0.0.1,reuseaddr,fork UNIX-CONNECT:${bridgeDirectory}/http.sock")
      {
        wantedBy = [ "multi-user.target" ];
        requires = [
          "systemd-tmpfiles-setup.service"
          "aurral-http-vpn.service"
        ];
        after = [
          "systemd-tmpfiles-setup.service"
          "aurral-http-vpn.service"
        ];
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
      MUSIC_ROOT = musicFolder;
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
    unitConfig.RequiresMountsFor = mediaMounts ++ [ musicFolder ];
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
    unitConfig.RequiresMountsFor = mediaMounts ++ [ musicFolder ];
    environment = {
      AURRAL_QUALITY_POLICY = toString qualityPolicy;
      AURRAL_DATA_DIR = "/var/lib/aurral";
      AURRAL_HOST = "127.0.0.1";
      PORT = "3001";
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
  system.activationScripts.aurral-artist-identity-repair-cleanup.text =
    (import ../../../../../../lib/templates/text.nix)
      ./scripts/aurral-artist-identity-repair-cleanup-text.sh
      { pkgs_coreutils = pkgs.coreutils; };

  system.activationScripts.aurral-request-quality-repair-cleanup.text =
    (import ../../../../../../lib/templates/text.nix)
      ./scripts/aurral-request-quality-repair-cleanup-text.sh
      { pkgs_coreutils = pkgs.coreutils; };

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
      AURRAL_URL = "http://127.0.0.1:3001";
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
      ExecStart = "${bootstrap} ${lib.escapeShellArg downloadFolder} ${lib.escapeShellArg musicFolder}";
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
      ExecStart = "${
        pkgs.writers.writePython3 "verify-listenbrainz-identity" {
          flakeIgnore = [
            "E501"
            "W503"
          ];
        } (builtins.readFile ./scripts/verify_listenbrainz_identity.py)
      } /run/aurral-listenbrainz-identity/validated.json";
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
      AURRAL_URL = "http://127.0.0.1:3001";
      LIDARR_URL = "http://127.0.0.1:${toString config.services.lidarr.settings.server.port}";
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
      ExecStartPre = "${lib.getExe pkgs.curl} --fail --silent --show-error --output /dev/null --retry 20 --retry-delay 2 --retry-connrefused --retry-all-errors --connect-timeout 2 --max-time 3 http://127.0.0.1:3001/api/health";
      ExecStart = "${bootstrap} ${lib.escapeShellArg downloadFolder} ${lib.escapeShellArg musicFolder}";
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
        lib.all
          (
            name:
            let
              unit = config.systemd.services.${name};
            in
            unit.vpn.enable
            && unit.vpn.namespace == namespace
            && unit.serviceConfig.NetworkNamespacePath == "/run/netns/${namespace}"
          )
          [
            "aurral-http-vpn"
            "aurral-lidarr-vpn"
            "aurral-listenbrainz-identity"
          ]
        &&
          lib.all
            (
              name:
              let
                unit = config.systemd.services.${name}.serviceConfig;
              in
              unit.IPAddressDeny == [ "any" ] && unit.IPAddressAllow == [ "127.0.0.0/8" ]
            )
            [
              "aurral-http-host"
              "aurral-lidarr-host"
              "aurral-library-rescan"
            ];
      message = "Aurral API bridges must preserve VPN confinement and loopback-only host access.";
    }
    {
      assertion =
        config.homelab.storage.enable
        && config.homelab.apps.lidarr.enable
        && config.homelab.apps.slskd.enable
        && config.services.navidrome.enable
        && config.services.navidrome.settings.MusicFolder == musicFolder
        && !(builtins.elem 3001 config.networking.firewall.allowedTCPPorts);
      message = "Aurral needs the homelab music services and Navidrome's music folder; its direct HTTP port must stay closed to the LAN.";
    }
  ];
}
