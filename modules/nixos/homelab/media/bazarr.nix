{ lib, config, ... }:
let
  cfg = config.homelab.media.bazarr;
in
{
  options.homelab.media.bazarr = {
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

    mediaGroup = lib.mkOption {
      type = lib.types.str;
      default = "media";
      description = "Shared media library group.";
    };
  };

  config = {
    services.nginx.virtualHosts."_".locations = lib.mkMerge [
      (lib.mkIf config.homelab.proxy.tailscaleTls.enable {
        "= /bazarr" = {
          return = "302 /bazarr/";
        };
        "/bazarr/" = {
          proxyPass = "http://127.0.0.1:${toString config.services.bazarr.listenPort}";
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
            proxy_set_header X-Forwarded-Prefix /bazarr;
          '';
        };
      })
    ];

    services.nginx.virtualHosts.vm-http.locations = lib.mkMerge [
      (lib.mkIf config.homelab.proxy.vmHttpAccess.enable {
        "= /bazarr" = {
          return = "302 /bazarr/";
        };
        "/bazarr/" = {
          proxyPass = "http://127.0.0.1:${toString config.services.bazarr.listenPort}";
          recommendedProxySettings = true;
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Proto http;
            proxy_set_header X-Forwarded-Prefix /bazarr;
          '';
        };
      })
    ];

    services.homepage-dashboard.services.Automation = [
      {
        Bazarr = {
          icon = "bazarr.png";
          href = "/bazarr/";
          description = "Subtitle fetching for the existing media stack.";
          weight = 50;
        };
      }
    ];

    users.groups.${config.services.bazarr.group} = { };
    users.groups.${cfg.downloadsGroup} = { };
    users.groups.${cfg.mediaGroup} = { };

    users.users.${config.services.bazarr.user}.extraGroups = lib.mkAfter [
      cfg.downloadsGroup
      cfg.mediaGroup
    ];

    systemd.tmpfiles.rules = [
      "d ${config.services.bazarr.dataDir} 0750 ${config.services.bazarr.user} ${config.services.bazarr.group} - -"
      "d ${cfg.stackRoot} 0755 root root - -"
      "d ${cfg.stackRoot}/data 0755 root root - -"
      "d ${cfg.stackRoot}/data/media 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/media/movies 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/media/tv 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/media/music 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/media/books 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/media/books/books 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/media/books/audiobooks 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/media/books/comics 2770 root ${cfg.mediaGroup} - -"
    ];

    services.bazarr = {
      enable = true;
      user = "bazarr";
      group = "bazarr";
      listenPort = 6767;
      openFirewall = false;
    };

    systemd.services.bazarr.serviceConfig.UMask = lib.mkForce "0002";
  };
}
