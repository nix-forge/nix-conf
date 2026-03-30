{ lib, config, ... }:
let
  cfg = config.homelab.media.radarr;
in
{
  options.homelab.media.radarr = {
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/radarr";
      description = "Radarr state directory.";
    };

    stackRoot = lib.mkOption {
      type = lib.types.str;
      default = "/srv/media-stack";
      description = "Shared media stack root.";
    };

    primaryGroup = lib.mkOption {
      type = lib.types.str;
      default = "radarr";
      description = "Primary group for Radarr service runtime.";
    };

    downloadsGroup = lib.mkOption {
      type = lib.types.str;
      default = "downloads";
      description = "Shared downloads group for media ingest workflow.";
    };

    mediaGroup = lib.mkOption {
      type = lib.types.str;
      default = "media";
      description = "Shared media library group.";
    };
  };

  config = {
    services.nginx.virtualHosts."_".locations = lib.mkMerge [
      (lib.mkIf config.homelab.proxy.tailscaleTls.enable {
        "= /radarr" = {
          return = "302 /radarr/";
        };
        "/radarr/" = {
          proxyPass = "http://127.0.0.1:7878";
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
            proxy_set_header X-Forwarded-Prefix /radarr;
          '';
        };
      })
    ];

    services.nginx.virtualHosts.vm-http.locations = lib.mkMerge [
      (lib.mkIf config.homelab.proxy.vmHttpAccess.enable {
        "= /radarr" = {
          return = "302 /radarr/";
        };
        "/radarr/" = {
          proxyPass = "http://127.0.0.1:7878";
          recommendedProxySettings = true;
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Proto http;
            proxy_set_header X-Forwarded-Prefix /radarr;
          '';
        };
      })
    ];

    services.homepage-dashboard.services.Automation = [
      {
        Radarr = {
          icon = "radarr.png";
          href = "/radarr/";
          description = "Movie collection and upgrade flow.";
          weight = 20;
        };
      }
    ];

    users.groups.${cfg.primaryGroup} = { };
    users.groups.${cfg.downloadsGroup} = { };
    users.groups.${cfg.mediaGroup} = { };

    users.users.radarr.extraGroups = lib.mkAfter [
      cfg.downloadsGroup
      cfg.mediaGroup
    ];

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 radarr ${cfg.primaryGroup} - -"
      "d ${cfg.stackRoot} 0755 root root - -"
      "d ${cfg.stackRoot}/data 0755 root root - -"
      "d ${cfg.stackRoot}/data/media 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/media/movies 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/torrents 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/data/torrents/movies 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/data/usenet 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/data/usenet/movies 2770 root ${cfg.downloadsGroup} - -"
    ];

    services.radarr = {
      enable = true;
      dataDir = cfg.stateDir;
      user = "radarr";
      group = cfg.primaryGroup;
      openFirewall = false;
      settings = {
        server = {
          port = 7878;
          bindaddress = "127.0.0.1";
          urlbase = "/radarr";
        };
      };
      environmentFiles = [ ];
    };

    systemd.services.radarr.serviceConfig.UMask = lib.mkForce "0002";
  };
}
