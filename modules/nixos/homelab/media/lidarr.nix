{ lib, config, ... }:
let
  cfg = config.homelab.media.lidarr;
in
{
  options.homelab.media.lidarr = {
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/lidarr";
      description = "Lidarr state directory.";
    };

    stackRoot = lib.mkOption {
      type = lib.types.str;
      default = "/srv/media-stack";
      description = "Shared media stack root.";
    };

    primaryGroup = lib.mkOption {
      type = lib.types.str;
      default = "lidarr";
      description = "Primary group for Lidarr service runtime.";
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
        "= /lidarr" = {
          return = "302 /lidarr/";
        };
        "/lidarr/" = {
          proxyPass = "http://127.0.0.1:8686";
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
            proxy_set_header X-Forwarded-Prefix /lidarr;
          '';
        };
      })
    ];

    services.nginx.virtualHosts.vm-http.locations = lib.mkMerge [
      (lib.mkIf config.homelab.proxy.vmHttpAccess.enable {
        "= /lidarr" = {
          return = "302 /lidarr/";
        };
        "/lidarr/" = {
          proxyPass = "http://127.0.0.1:8686";
          recommendedProxySettings = true;
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Proto http;
            proxy_set_header X-Forwarded-Prefix /lidarr;
          '';
        };
      })
    ];

    services.homepage-dashboard.services.Automation = [
      {
        Lidarr = {
          icon = "lidarr.png";
          href = "/lidarr/";
          description = "Music acquisition and metadata cleanup.";
          weight = 30;
        };
      }
    ];

    users.groups.${cfg.primaryGroup} = { };
    users.groups.${cfg.downloadsGroup} = { };
    users.groups.${cfg.mediaGroup} = { };

    users.users.lidarr.extraGroups = lib.mkAfter [
      cfg.downloadsGroup
      cfg.mediaGroup
    ];

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 lidarr ${cfg.primaryGroup} - -"
      "d ${cfg.stackRoot} 0755 root root - -"
      "d ${cfg.stackRoot}/data 0755 root root - -"
      "d ${cfg.stackRoot}/data/media 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/media/music 2770 root ${cfg.mediaGroup} - -"
    ];

    services.lidarr = {
      enable = true;
      dataDir = cfg.stateDir;
      user = "lidarr";
      group = cfg.primaryGroup;
      openFirewall = false;
      settings = {
        server = {
          port = 8686;
          bindaddress = "127.0.0.1";
          urlbase = "/lidarr";
        };
      };
      environmentFiles = [ ];
    };

    systemd.services.lidarr.serviceConfig.UMask = lib.mkForce "0002";
  };
}
