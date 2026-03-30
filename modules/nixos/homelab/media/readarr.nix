{ lib, config, ... }:
let
  cfg = config.homelab.media.readarr;
in
{
  options.homelab.media.readarr = {
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/readarr";
      description = "Readarr state directory.";
    };

    stackRoot = lib.mkOption {
      type = lib.types.str;
      default = "/srv/media-stack";
      description = "Shared media stack root.";
    };

    primaryGroup = lib.mkOption {
      type = lib.types.str;
      default = "readarr";
      description = "Primary group for Readarr service runtime.";
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
        "= /readarr" = {
          return = "302 /readarr/";
        };
        "/readarr/" = {
          proxyPass = "http://127.0.0.1:8787";
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
            proxy_set_header X-Forwarded-Prefix /readarr;
          '';
        };
      })
    ];

    services.nginx.virtualHosts.vm-http.locations = lib.mkMerge [
      (lib.mkIf config.homelab.proxy.vmHttpAccess.enable {
        "= /readarr" = {
          return = "302 /readarr/";
        };
        "/readarr/" = {
          proxyPass = "http://127.0.0.1:8787";
          recommendedProxySettings = true;
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Proto http;
            proxy_set_header X-Forwarded-Prefix /readarr;
          '';
        };
      })
    ];

    services.homepage-dashboard.services.Automation = [
      {
        Readarr = {
          icon = "readarr.png";
          href = "/readarr/";
          description = "Books and audiobooks pipeline.";
          weight = 40;
        };
      }
    ];

    users.groups.${cfg.primaryGroup} = { };
    users.groups.${cfg.downloadsGroup} = { };
    users.groups.${cfg.mediaGroup} = { };

    users.users.readarr.extraGroups = lib.mkAfter [
      cfg.downloadsGroup
      cfg.mediaGroup
    ];

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 readarr ${cfg.primaryGroup} - -"
      "d ${cfg.stackRoot} 0755 root root - -"
      "d ${cfg.stackRoot}/data 0755 root root - -"
      "d ${cfg.stackRoot}/data/media 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/media/books 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/media/books/books 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/media/books/audiobooks 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/media/books/comics 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/torrents 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/data/torrents/books 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/data/usenet 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/data/usenet/books 2770 root ${cfg.downloadsGroup} - -"
    ];

    services.readarr = {
      enable = true;
      dataDir = cfg.stateDir;
      user = "readarr";
      group = cfg.primaryGroup;
      openFirewall = false;
      settings = {
        server = {
          port = 8787;
          bindaddress = "127.0.0.1";
          urlbase = "/readarr";
        };
      };
      environmentFiles = [ ];
    };

    systemd.services.readarr.serviceConfig.UMask = lib.mkForce "0002";
  };
}
