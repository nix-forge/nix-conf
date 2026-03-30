{ lib, config, ... }:
let
  cfg = config.homelab.media.radarr;
in
{
  options.homelab.media.radarr = {
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
        "= ${config.services.radarr.settings.server.urlbase}" = {
          return = "302 ${config.services.radarr.settings.server.urlbase}/";
        };
        "${config.services.radarr.settings.server.urlbase}/" = {
          proxyPass = "http://${config.services.radarr.settings.server.bindaddress}:${config.services.radarr.settings.server.port}";
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
            proxy_set_header X-Forwarded-Prefix ${config.services.radarr.settings.server.urlbase};
          '';
        };
      })
    ];

    services.nginx.virtualHosts.vm-http.locations = lib.mkMerge [
      (lib.mkIf config.homelab.proxy.vmHttpAccess.enable {
        "= ${config.services.radarr.settings.server.urlbase}" = {
          return = "302 ${config.services.radarr.settings.server.urlbase}/";
        };
        "${config.services.radarr.settings.server.urlbase}/" = {
          proxyPass = "http://${config.services.radarr.settings.server.bindaddress}:${config.services.radarr.settings.server.port}";
          recommendedProxySettings = true;
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Proto http;
            proxy_set_header X-Forwarded-Prefix ${config.services.radarr.settings.server.urlbase};
          '';
        };
      })
    ];

    services.homepage-dashboard.services.Automation = [
      {
        Radarr = {
          icon = "radarr.png";
          href = "${config.services.radarr.settings.server.urlbase}/";
          description = "Movie collection and upgrade flow.";
          weight = 20;
        };
      }
    ];

    users.groups.${config.services.radarr.group} = { };
    users.groups.${cfg.downloadsGroup} = { };
    users.groups.${cfg.mediaGroup} = { };

    users.users.${config.services.radarr.user}.extraGroups = lib.mkAfter [
      cfg.downloadsGroup
      cfg.mediaGroup
    ];

    systemd.tmpfiles.rules = [
      "d ${config.services.radarr.dataDir} 0750 ${config.services.radarr.user} ${config.services.radarr.group} - -"
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
      user = "radarr";
      group = "radarr";
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
