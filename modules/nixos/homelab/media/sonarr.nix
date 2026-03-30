{ lib, config, ... }:
let
  cfg = config.homelab.media.sonarr;
in
{
  options.homelab.media.sonarr = {
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
    services.nginx.virtualHosts."_".locations = {
      "= ${config.services.sonarr.settings.server.urlbase}" = {
        return = "302 ${config.services.sonarr.settings.server.urlbase}/";
      };
      "${config.services.sonarr.settings.server.urlbase}/" = {
        proxyPass = "http://${config.services.sonarr.settings.server.bindaddress}:${toString config.services.sonarr.settings.server.port}";
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
          proxy_set_header X-Forwarded-Prefix ${config.services.sonarr.settings.server.urlbase};
        '';
      };
    };

    services.homepage-dashboard.services.Automation = [
      {
        Sonarr = {
          icon = "sonarr.png";
          href = "${config.services.sonarr.settings.server.urlbase}/";
          description = "Series intake and release automation.";
          weight = 10;
        };
      }
    ];

    users.groups.${config.services.sonarr.group} = { };
    users.groups.${cfg.downloadsGroup} = { };
    users.groups.${cfg.mediaGroup} = { };

    users.users.${config.services.sonarr.user}.extraGroups = lib.mkAfter [
      cfg.downloadsGroup
      cfg.mediaGroup
    ];

    systemd.tmpfiles.rules = [
      "d ${config.services.sonarr.dataDir} 0750 ${config.services.sonarr.user} ${config.services.sonarr.group} - -"
      "d ${cfg.stackRoot} 0755 root root - -"
      "d ${cfg.stackRoot}/data 0755 root root - -"
      "d ${cfg.stackRoot}/data/media 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/media/tv 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/torrents 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/data/torrents/tv 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/data/usenet 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/data/usenet/tv 2770 root ${cfg.downloadsGroup} - -"
    ];

    services.sonarr = {
      enable = true;
      user = "sonarr";
      group = "sonarr";
      openFirewall = false;
      settings = {
        server = {
          port = 8989;
          bindaddress = "127.0.0.1";
          urlbase = "/sonarr";
        };
      };
      environmentFiles = [ ];
    };

    systemd.services.sonarr.serviceConfig.UMask = lib.mkForce "0002";
  };
}
