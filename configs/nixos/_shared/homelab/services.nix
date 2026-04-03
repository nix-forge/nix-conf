{
  profile ? "home-server",
}:
{ config, lib, ... }:
let
  stack = import ./stack-values.nix { inherit profile; };
  reconcileEnv = config.age.secrets.homelab-reconcile-env.path;
in
{
  assertions = [
    {
      assertion = lib.hasAttrByPath [ "age" "secrets" "vaultwarden-admin-token" ] config;
      message = "age.secrets.vaultwarden-admin-token must exist for homelab services.";
    }
    {
      assertion = lib.hasAttrByPath [ "age" "secrets" "homelab-reconcile-env" ] config;
      message = "age.secrets.homelab-reconcile-env must exist for homelab services.";
    }
  ];

  networking.firewall.enable = true;
  networking.wireguard = {
    enable = true;
    useNetworkd = true;
  };

  services = {
    resolved.enable = true;
    openssh.enable = true;
    fail2ban.enable = true;
    caddy.enable = true;
    homepage-dashboard.enable = true;

    jellyfin.enable = true;
    seerr = {
      enable = true;
      inherit (stack.services.seerr) port;
    };

    sonarr = {
      enable = true;
      settings.server.port = stack.services.sonarr.port;
      environmentFiles = [ reconcileEnv ];
    };

    radarr = {
      enable = true;
      settings.server.port = stack.services.radarr.port;
      environmentFiles = [ reconcileEnv ];
    };

    lidarr = {
      enable = true;
      settings.server.port = stack.services.lidarr.port;
      environmentFiles = [ reconcileEnv ];
    };

    readarr = {
      enable = true;
      settings.server.port = stack.services.readarr.port;
      environmentFiles = [ reconcileEnv ];
    };

    bazarr = {
      enable = true;
      listenPort = stack.services.bazarr.port;
    };

    prowlarr = {
      enable = true;
      settings.server.port = stack.services.prowlarr.port;
      environmentFiles = [ reconcileEnv ];
    };

    qbittorrent = {
      enable = true;
      inherit (stack.services.qbittorrent) webuiPort;
      inherit (stack.services.qbittorrent) torrentingPort;
      serverConfig.Preferences.WebUI = {
        Username = "admin";
        Password_PBKDF2 = "SJGGqPhUDVEhr+m1jHZyzw==:OoDJ//z3Bvq1q8OypIkxo5XlNWajUYBh4QHxNPRKHPMFXki5lYcLO+xDquE5sVuxG68qZzFGhkHkVrAJLOG6Gg==";
      };
    };

    nzbget = {
      enable = true;
      settings = {
        ControlPort = stack.services.nzbget.controlPort;
        "Category5.Name" = "Books";
        "Category6.Name" = "Prowlarr";
      };
    };

    vaultwarden = {
      enable = true;
      config = {
        ROCKET_PORT = stack.services.vaultwarden.rocketPort;
        SIGNUPS_ALLOWED = false;
      };
      environmentFile = config.age.secrets.vaultwarden-admin-token.path;
    };

    flaresolverr.enable = true;
  };

  systemd.services.seerr.serviceConfig.EnvironmentFile = [ reconcileEnv ];

  imports = [
    ((import ./ops-monitoring.nix) { inherit profile; })
    ((import ./ops-backup.nix) { inherit profile; })
    ((import ./ops-alerting.nix) { inherit profile; })
    ((import ./ops-logging.nix) { inherit profile; })
  ];
}
