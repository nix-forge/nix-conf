{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.homelab.media.nzbget;
in
{
  options.homelab.media.nzbget = {
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
    services.nginx.virtualHosts."_".locations = lib.mkMerge [
      (lib.mkIf config.homelab.proxy.tailscaleTls.enable {
        "= /nzbget" = {
          return = "302 /nzbget/";
        };
        "/nzbget/" = {
          proxyPass = "http://${config.services.nzbget.settings.ControlIP}:${toString config.services.nzbget.settings.ControlPort}";
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
            proxy_set_header X-Forwarded-Prefix /nzbget;
          '';
        };
      })
    ];

    services.nginx.virtualHosts.vm-http.locations = lib.mkMerge [
      (lib.mkIf config.homelab.proxy.vmHttpAccess.enable {
        "= /nzbget" = {
          return = "302 /nzbget/";
        };
        "/nzbget/" = {
          proxyPass = "http://${config.services.nzbget.settings.ControlIP}:${toString config.services.nzbget.settings.ControlPort}";
          recommendedProxySettings = true;
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Proto http;
            proxy_set_header X-Forwarded-Prefix /nzbget;
          '';
        };
      })
    ];

    services.homepage-dashboard.services.Downloads = [
      {
        NZBGet = {
          icon = "nzbget.png";
          href = "/nzbget/";
          description = "Usenet queue and unpacking path, still loopback-only.";
          weight = 20;
        };
      }
    ];

    users.groups.${config.services.nzbget.group} = { };
    users.groups.${cfg.downloadsGroup} = { };

    users.users.${config.services.nzbget.user}.extraGroups = lib.mkAfter [ cfg.downloadsGroup ];

    systemd.tmpfiles.rules = [
      "d /var/lib/nzbget 0750 ${config.services.nzbget.user} ${config.services.nzbget.group} - -"
      "d ${cfg.stackRoot} 0755 root root - -"
      "d ${cfg.stackRoot}/data 0755 root root - -"
      "d ${cfg.stackRoot}/data/usenet 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/data/usenet/incomplete 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/data/usenet/movies 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/data/usenet/tv 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/data/usenet/music 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/data/usenet/books 2770 root ${cfg.downloadsGroup} - -"
    ];

    services.nzbget = {
      enable = true;
      package = pkgs.nzbget;
      user = "nzbget";
      group = "nzbget";
      # TODO: Configure the correct settings using documentation from https://github.com/nzbgetcom/nzbget/blob/develop/nzbget.conf
      settings = {
        ControlIP = "127.0.0.1";
        ControlPort = 6789;
      };
    };

    systemd.services.nzbget.serviceConfig.UMask = lib.mkForce "0002";

  };
}
