{ lib, ... }:
let
  inherit (lib) mkEnableOption mkOption types;
in
{
  options.my.media = {
    enable = mkEnableOption "media server stack";

    network = {
      manageHostNetworking = mkOption {
        type = types.bool;
        default = true;
      };
      interface = mkOption {
        type = types.str;
        default = "";
      };
      lanAddress = mkOption {
        type = types.str;
        default = "";
      };
      lanPrefixLength = mkOption {
        type = types.int;
        default = 24;
      };
      lanCidrs = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      enableIPv6 = mkOption {
        type = types.bool;
        default = false;
      };
      trustedProxyCidrs = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      nameservers = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
    };

    storage = {
      diskId = mkOption {
        type = types.str;
        default = "";
      };
      stateDir = mkOption {
        type = types.str;
        default = "/srv/state";
      };
      mediaDir = mkOption {
        type = types.str;
        default = "/srv/media";
      };
      downloadsDir = mkOption {
        type = types.str;
        default = "/srv/downloads";
      };
      moviesDir = mkOption {
        type = types.str;
        default = "/srv/media/movies";
      };
      showsDir = mkOption {
        type = types.str;
        default = "/srv/media/tv";
      };
      torrentDir = mkOption {
        type = types.str;
        default = "/srv/downloads/torrents";
      };
      usenetDir = mkOption {
        type = types.str;
        default = "/srv/downloads/usenet";
      };
      swapSize = mkOption {
        type = types.str;
        default = "16G";
      };
    };

    downloaders = {
      qbittorrent = {
        name = mkOption {
          type = types.str;
          default = "qBittorrent";
        };
        host = mkOption {
          type = types.str;
          default = "127.0.0.1";
        };
        categoryMovies = mkOption {
          type = types.str;
          default = "radarr";
        };
        categoryShows = mkOption {
          type = types.str;
          default = "sonarr";
        };
      };

      nzbget = {
        name = mkOption {
          type = types.str;
          default = "NZBGet";
        };
        host = mkOption {
          type = types.str;
          default = "127.0.0.1";
        };
        categoryMovies = mkOption {
          type = types.str;
          default = "movies";
        };
        categoryShows = mkOption {
          type = types.str;
          default = "tv";
        };
      };
    };

    hosts = {
      vaultwarden = mkOption {
        type = types.str;
        default = "";
      };
      jellyfin = mkOption {
        type = types.str;
        default = "";
      };
      jellyseerr = mkOption {
        type = types.str;
        default = "";
      };
      radarr = mkOption {
        type = types.str;
        default = "";
      };
      sonarr = mkOption {
        type = types.str;
        default = "";
      };
      prowlarr = mkOption {
        type = types.str;
        default = "";
      };
      bazarr = mkOption {
        type = types.str;
        default = "";
      };
      qbittorrent = mkOption {
        type = types.str;
        default = "";
      };
      nzbget = mkOption {
        type = types.str;
        default = "";
      };
      homebridge = mkOption {
        type = types.str;
        default = "";
      };
      scrypted = mkOption {
        type = types.str;
        default = "";
      };
      pihole = mkOption {
        type = types.str;
        default = "";
      };
      vaultwardenPublic = mkOption {
        type = types.str;
        default = "";
      };
      jellyfinPublic = mkOption {
        type = types.str;
        default = "";
      };
      jellyseerrPublic = mkOption {
        type = types.str;
        default = "";
      };
    };

    ports = {
      ssh = mkOption {
        type = types.port;
        default = 22;
      };
      traefikHttp = mkOption {
        type = types.port;
        default = 80;
      };
      traefikHttps = mkOption {
        type = types.port;
        default = 443;
      };
      jellyfin = mkOption {
        type = types.port;
        default = 8096;
      };
      jellyseerr = mkOption {
        type = types.port;
        default = 5055;
      };
      vaultwarden = mkOption {
        type = types.port;
        default = 8222;
      };
      radarr = mkOption {
        type = types.port;
        default = 7878;
      };
      sonarr = mkOption {
        type = types.port;
        default = 8989;
      };
      prowlarr = mkOption {
        type = types.port;
        default = 9696;
      };
      bazarr = mkOption {
        type = types.port;
        default = 6767;
      };
      qbittorrent = mkOption {
        type = types.port;
        default = 8081;
      };
      nzbget = mkOption {
        type = types.port;
        default = 6789;
      };
      homebridge = mkOption {
        type = types.port;
        default = 8581;
      };
      scrypted = mkOption {
        type = types.port;
        default = 10443;
      };
      pihole = mkOption {
        type = types.port;
        default = 8080;
      };
      dns = mkOption {
        type = types.port;
        default = 53;
      };
    };

    services = {
      traefik.enable = mkOption {
        type = types.bool;
        default = true;
      };
      arr.enable = mkOption {
        type = types.bool;
        default = true;
      };
      jellyfin.enable = mkOption {
        type = types.bool;
        default = true;
      };
      jellyseerr.enable = mkOption {
        type = types.bool;
        default = true;
      };
      vaultwarden.enable = mkOption {
        type = types.bool;
        default = true;
      };
      ddns.enable = mkOption {
        type = types.bool;
        default = true;
      };
      torrent.enable = mkOption {
        type = types.bool;
        default = true;
      };
      pihole.enable = mkOption {
        type = types.bool;
        default = true;
      };
      homebridge.enable = mkOption {
        type = types.bool;
        default = true;
      };
      scrypted.enable = mkOption {
        type = types.bool;
        default = true;
      };
      cloudflared.enable = mkOption {
        type = types.bool;
        default = false;
      };
      fail2ban.enable = mkOption {
        type = types.bool;
        default = true;
      };
    };

    ddns = {
      zone = mkOption {
        type = types.str;
        default = "";
      };
      domain = mkOption {
        type = types.str;
        default = "";
      };
      interval = mkOption {
        type = types.str;
        default = "5min";
      };
    };

    cloudflare = {
      tunnelId = mkOption {
        type = types.str;
        default = "";
      };
      accessProtectedHosts = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      accessAudTag = mkOption {
        type = types.str;
        default = "";
      };
    };

    secrets = {
      cloudflareDdnsToken = mkOption {
        type = types.str;
        default = "";
      };
      vaultwardenEnv = mkOption {
        type = types.str;
        default = "";
      };
      vpnGluetunEnv = mkOption {
        type = types.str;
        default = "";
      };
      qbittorrentEnv = mkOption {
        type = types.str;
        default = "";
      };
      piholeEnv = mkOption {
        type = types.str;
        default = "";
      };
      cloudflaredCreds = mkOption {
        type = types.str;
        default = "";
      };
      cloudflaredCert = mkOption {
        type = types.str;
        default = "";
      };
      homebridgeEnv = mkOption {
        type = types.str;
        default = "";
      };
      scryptedEnv = mkOption {
        type = types.str;
        default = "";
      };
      qbittorrentWebuiPassword = mkOption {
        type = types.str;
        default = "";
      };
    };
  };
}
