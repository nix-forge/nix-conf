{ lib, config, ... }:
let
  cfg = config.homelab.media.seerr;
in
{
  options.homelab.media.seerr = {
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/seerr";
      description = "Seerr state directory.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "seerr";
      description = "Seerr service user.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "seerr";
      description = "Seerr service group.";
    };
  };

  config = {
    services.nginx.virtualHosts."_".locations = lib.mkMerge [
      (lib.mkIf config.homelab.proxy.tailscaleTls.enable {
        "= /seerr" = {
          return = "302 /seerr/";
        };
        "/seerr/" = {
          proxyPass = "http://127.0.0.1:5055/";
          recommendedProxySettings = true;
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Proto https;
            proxy_set_header X-Forwarded-Prefix /seerr;
            proxy_set_header Accept-Encoding "";
            sub_filter_once off;
            sub_filter_types text/html application/javascript text/javascript text/css;
            sub_filter 'href="/' 'href="/seerr/';
            sub_filter 'src="/' 'src="/seerr/';
            sub_filter 'content="/' 'content="/seerr/';
            sub_filter 'url(/' 'url(/seerr/';
            sub_filter '"/_next/' '"/seerr/_next/';
            sub_filter "'/_next/" "'/seerr/_next/";
            proxy_redirect ~^(/.*)$ /seerr$1;
          '';
        };
      })
    ];

    services.nginx.virtualHosts.vm-http.locations = lib.mkMerge [
      (lib.mkIf config.homelab.proxy.vmHttpAccess.enable {
        "= /seerr" = {
          return = "302 /seerr/";
        };
        "/seerr/" = {
          proxyPass = "http://127.0.0.1:5055/";
          recommendedProxySettings = true;
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Proto http;
            proxy_set_header X-Forwarded-Prefix /seerr;
            proxy_set_header Accept-Encoding "";
            sub_filter_once off;
            sub_filter_types text/html application/javascript text/javascript text/css;
            sub_filter 'href="/' 'href="/seerr/';
            sub_filter 'src="/' 'src="/seerr/';
            sub_filter 'content="/' 'content="/seerr/';
            sub_filter 'url(/' 'url(/seerr/';
            sub_filter '"/_next/' '"/seerr/_next/';
            sub_filter "'/_next/" "'/seerr/_next/";
            proxy_redirect ~^(/.*)$ /seerr$1;
          '';
        };
      })
    ];

    services.homepage-dashboard.services.Media = [
      {
        Seerr = {
          icon = "seerr.png";
          href = "/seerr/";
          description = "Requests and discovery, proxied through the single tailnet origin.";
          weight = 20;
        };
      }
    ];

    services.seerr = {
      enable = true;
      port = 5055;
      openFirewall = false;
    };

    users.groups.${cfg.group} = { };
    users.users.${cfg.user} = {
      isSystemUser = true;
      inherit (cfg) group;
    };

    systemd.tmpfiles.rules = [ "d ${cfg.stateDir} 0750 ${cfg.user} ${cfg.group} - -" ];

    systemd.services.seerr.serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = lib.mkForce cfg.user;
      Group = lib.mkForce cfg.group;
    };
  };
}
