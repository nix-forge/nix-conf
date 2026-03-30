{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.media.qbittorrent;
in
{
  options.homelab.media.qbittorrent = {
    bindToMullvad = lib.mkOption {
      type = lib.types.bool;
      default = config.networking.wireguard.enable;
      description = "Bind qBittorrent to wg-mullvad when WireGuard is enabled.";
    };

    stackRoot = lib.mkOption {
      type = lib.types.str;
      default = "/srv/media-stack";
      description = "Shared media stack root.";
    };

    downloadsGroup = lib.mkOption {
      type = lib.types.str;
      default = "downloads";
      description = "Shared downloads group for media ingest workflow.";
    };
  };

  config = {
    assertions = [
      {
        assertion = (!cfg.bindToMullvad) || config.networking.wireguard.enable;
        message = "homelab.media.qbittorrent.bindToMullvad requires networking.wireguard.enable = true";
      }
    ];

    users.groups.${config.services.qbittorrent.group} = { };
    users.groups.${cfg.downloadsGroup} = { };

    users.users.qbittorrent.extraGroups = lib.mkAfter [ cfg.downloadsGroup ];

    services.nginx.virtualHosts."_".locations = {
      "= /qbittorrent" = {
        return = "302 /qbittorrent/";
      };
      "/qbittorrent/" = {
        proxyPass = "http://${config.services.qbittorrent.serverConfig.Preferences.WebUI.Address}:${toString config.services.qbittorrent.webuiPort}/";
        recommendedProxySettings = true;
        proxyWebsockets = true;
        extraConfig = ''
          auth_request /_tailscale-auth;
          auth_request_set $auth_user $upstream_http_tailscale_user;
          auth_request_set $auth_name $upstream_http_tailscale_name;
          auth_request_set $auth_login $upstream_http_tailscale_login;
          auth_request_set $auth_tailnet $upstream_http_tailscale_tailnet;
          auth_request_set $auth_profile_picture $upstream_http_tailscale_profile_picture;

          proxy_set_header X-Webauth-User "$auth_user";
          proxy_set_header X-Webauth-Name "$auth_name";
          proxy_set_header X-Webauth-Login "$auth_login";
          proxy_set_header X-Webauth-Tailnet "$auth_tailnet";
          proxy_set_header X-Webauth-Profile-Picture "$auth_profile_picture";
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Host $host;
          proxy_set_header X-Forwarded-Proto https;
          proxy_set_header X-Forwarded-Prefix /qbittorrent;
          proxy_set_header Referer "";
          proxy_set_header Host $proxy_host;
          proxy_cookie_path / "/; Secure";
        '';
      };
    };

    services.homepage-dashboard.services.Downloads = [
      {
        qBittorrent = {
          icon = "qbittorrent.png";
          href = "/qbittorrent/";
          description = "Torrent client pinned to Mullvad with reverse-proxy support enabled.";
          weight = 10;
        };
      }
    ];

    systemd.tmpfiles.rules = [
      "d ${config.services.qbittorrent.profileDir} 0750 ${config.services.qbittorrent.user} ${config.services.qbittorrent.group} - -"
      "d ${cfg.stackRoot} 0755 root root - -"
      "d ${cfg.stackRoot}/data 0755 root root - -"
      "d ${cfg.stackRoot}/data/torrents 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/data/torrents/incomplete 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/data/torrents/movies 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/data/torrents/tv 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/data/torrents/music 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/data/torrents/books 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/cache 0755 root root - -"
      "d ${cfg.stackRoot}/cache/qbittorrent 2770 root ${cfg.downloadsGroup} - -"
    ];

    services.qbittorrent = {
      enable = true;
      package = pkgs.qbittorrent-nox;
      user = "qbittorrent";
      group = "qbittorrent";
      webuiPort = 8081;
      torrentingPort = 51413;
      openFirewall = false;
      serverConfig = {
        Preferences = {
          WebUI = {
            Address = "127.0.0.1";
            ReverseProxySupportEnabled = true;
          };
        }
        // (lib.optionalAttrs cfg.bindToMullvad {
          Connection = {
            Interface = "wg-mullvad";
            InterfaceAddress = "10.71.216.231";
          };
        });
      };
    };

    systemd.services.qbittorrent.serviceConfig.UMask = lib.mkForce "0002";
  };
}
