{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.homelab.media.prowlarr;
in
{
  options.homelab.media.prowlarr = {
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/prowlarr";
      description = "Prowlarr state directory.";
    };

    primaryGroup = lib.mkOption {
      type = lib.types.str;
      default = "prowlarr";
      description = "Primary group for Prowlarr service runtime.";
    };
  };

  config = {
    services.nginx.virtualHosts."_".locations = lib.mkMerge [
      (lib.mkIf config.homelab.proxy.tailscaleTls.enable {
        "= /prowlarr" = {
          return = "302 /prowlarr/";
        };
        "/prowlarr/" = {
          proxyPass = "http://127.0.0.1:9696";
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
            proxy_set_header X-Forwarded-Prefix /prowlarr;
          '';
        };
      })
    ];

    services.nginx.virtualHosts.vm-http.locations = lib.mkMerge [
      (lib.mkIf config.homelab.proxy.vmHttpAccess.enable {
        "= /prowlarr" = {
          return = "302 /prowlarr/";
        };
        "/prowlarr/" = {
          proxyPass = "http://127.0.0.1:9696";
          recommendedProxySettings = true;
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Proto http;
            proxy_set_header X-Forwarded-Prefix /prowlarr;
          '';
        };
      })
    ];

    services.homepage-dashboard.services.Automation = [
      {
        Prowlarr = {
          icon = "prowlarr.png";
          href = "/prowlarr/";
          description = "Indexer management behind localhost-only services.";
          weight = 60;
        };
      }
    ];

    users.groups.${cfg.primaryGroup} = { };

    systemd.tmpfiles.rules = [ "d ${cfg.stateDir} 0750 prowlarr ${cfg.primaryGroup} - -" ];

    services.prowlarr = {
      enable = true;
      package = pkgs.prowlarr;
      dataDir = cfg.stateDir;
      openFirewall = false;
      settings = {
        server = {
          port = 9696;
          bindaddress = "127.0.0.1";
          urlbase = "/prowlarr";
        };
      };
    };

    systemd.services.prowlarr.serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = lib.mkForce "prowlarr";
      Group = lib.mkForce cfg.primaryGroup;
    };
  };
}
