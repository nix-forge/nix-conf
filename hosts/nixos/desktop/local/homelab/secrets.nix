# These declarations expose missing credentials through nix-seal's bootstrap
# plan. Values are created and sealed on the administrator host, never here.
_: {
  nixSeal.secrets = {
    homelab-sonarr-username = {
      phase = "services";
      restartUnits = [ "homelab-web-auth-sonarr.service" ];
    };
    homelab-sonarr-password = {
      phase = "services";
      restartUnits = [ "homelab-web-auth-sonarr.service" ];
    };
    homelab-radarr-username = {
      phase = "services";
      restartUnits = [ "homelab-web-auth-radarr.service" ];
    };
    homelab-radarr-password = {
      phase = "services";
      restartUnits = [ "homelab-web-auth-radarr.service" ];
    };
    homelab-lidarr-username = {
      phase = "services";
      restartUnits = [ "homelab-web-auth-lidarr.service" ];
    };
    homelab-lidarr-password = {
      phase = "services";
      restartUnits = [ "homelab-web-auth-lidarr.service" ];
    };
    homelab-prowlarr-username = {
      phase = "services";
      restartUnits = [ "homelab-web-auth-prowlarr.service" ];
    };
    homelab-prowlarr-password = {
      phase = "services";
      restartUnits = [ "homelab-web-auth-prowlarr.service" ];
    };
    homelab-bazarr-username = {
      phase = "services";
      restartUnits = [ "homelab-web-auth-bazarr.service" ];
    };
    homelab-bazarr-password = {
      phase = "services";
      restartUnits = [ "homelab-web-auth-bazarr.service" ];
    };
    homelab-jellyfin-admin-username = {
      phase = "services";
      restartUnits = [
        "homelab-integrate-jellyfin.service"
        "homelab-integrate-seerr.service"
      ];
    };
    homelab-jellyfin-viewer-username = {
      phase = "services";
      restartUnits = [
        "homelab-integrate-jellyfin.service"
        "homelab-integrate-seerr.service"
      ];
    };
    homelab-seerr-admin-email = {
      phase = "services";
      restartUnits = [ "homelab-integrate-seerr.service" ];
    };
    homelab-indexer-proxy-username = {
      phase = "services";
      restartUnits = [
        "microsocks.service"
        "homelab-integrate-prowlarr.service"
      ];
    };
    homelab-navidrome-admin-username = {
      phase = "services";
      restartUnits = [ "music-discovery-bootstrap.service" ];
    };
    homelab-navidrome-service-username = {
      phase = "services";
      restartUnits = [ "music-discovery-bootstrap.service" ];
    };
    homelab-navidrome-listener-username = {
      phase = "services";
      restartUnits = [ "music-discovery-bootstrap.service" ];
    };
    homelab-aurral-admin-username = {
      phase = "services";
      restartUnits = [ "aurral-bootstrap.service" ];
    };
    homelab-aurral-admin-password = {
      phase = "services";
      restartUnits = [ "aurral-bootstrap.service" ];
    };
    homelab-qbittorrent-username.phase = "services";
    homelab-qbittorrent-password.phase = "services";
    homelab-qbittorrent-password-hash.phase = "services";
    homelab-qbittorrent-api-key.phase = "services";
    homelab-sonarr-api-key.phase = "services";
    homelab-radarr-api-key.phase = "services";
    homelab-lidarr-api-key.phase = "services";
    homelab-prowlarr-api-key.phase = "services";
    homelab-prowlarr-indexers.phase = "services";
    homelab-indexer-proxy-password = {
      phase = "services";
      restartUnits = [
        "microsocks.service"
        "homelab-integrate-prowlarr.service"
      ];
    };
    homelab-bazarr-api-key.phase = "services";
    homelab-subdl-api-key = {
      phase = "services";
      restartUnits = [ "homelab-integrate-bazarr.service" ];
    };
    homelab-jellyfin-admin-password = {
      phase = "services";
      restartUnits = [
        "homelab-integrate-jellyfin.service"
        "homelab-integrate-seerr.service"
      ];
    };
    homelab-jellyfin-viewer-password = {
      phase = "services";
      restartUnits = [
        "homelab-integrate-jellyfin.service"
        "homelab-integrate-seerr.service"
      ];
    };
    homelab-pocket-id-encryption-key.phase = "services";
    homelab-identity-realm.phase = "services";
    homelab-identity-admin-env.phase = "services";
    homelab-wardrowbe-env.phase = "services";
    homelab-miniflux-username.phase = "services";
    homelab-miniflux-password.phase = "services";
  };

  nixSeal.templates = {
    homelab-miniflux-admin-env = {
      content = ''
        ADMIN_USERNAME={{nix-seal:homelab-miniflux-username}}
        ADMIN_PASSWORD={{nix-seal:homelab-miniflux-password}}
      '';
      phase = "services";
      restartUnits = [ "miniflux.service" ];
    };
    homelab-qbittorrent-webui-ini = {
      content = ''
        [Preferences]
        WebUI\Username={{nix-seal:homelab-qbittorrent-username}}
        WebUI\Password_PBKDF2={{nix-seal:homelab-qbittorrent-password-hash}}
      '';
      phase = "services";
      restartUnits = [ "qbittorrent.service" ];
    };
    homelab-qbittorrent-login-json = {
      content = ''
        {"username":"{{nix-seal:homelab-qbittorrent-username}}","password":"{{nix-seal:homelab-qbittorrent-password}}"}
      '';
      phase = "services";
      restartUnits = [ "homelab-storage-pressure.service" ];
    };
  };

}
