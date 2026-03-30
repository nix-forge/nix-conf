{
  config,
  pkgs,
  lib,
  ...
}:
{
  services.nginx.virtualHosts."_".locations = lib.mkMerge [
    (lib.mkIf config.homelab.proxy.tailscaleTls.enable {
      "= ${config.services.prowlarr.settings.server.urlbase}" = {
        return = "302 ${config.services.prowlarr.settings.server.urlbase}/";
      };
      "${config.services.prowlarr.settings.server.urlbase}/" = {
        proxyPass = "http://${config.services.prowlarr.settings.server.bindaddress}:${toString config.services.prowlarr.settings.server.port}";
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
          proxy_set_header X-Forwarded-Prefix ${config.services.prowlarr.settings.server.urlbase};
        '';
      };
    })
  ];

  services.nginx.virtualHosts.vm-http.locations = lib.mkMerge [
    (lib.mkIf config.homelab.proxy.vmHttpAccess.enable {
      "= ${config.services.prowlarr.settings.server.urlbase}" = {
        return = "302 ${config.services.prowlarr.settings.server.urlbase}/";
      };
      "${config.services.prowlarr.settings.server.urlbase}/" = {
        proxyPass = "http://${config.services.prowlarr.settings.server.bindaddress}:${toString config.services.prowlarr.settings.server.port}";
        recommendedProxySettings = true;
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Host $host;
          proxy_set_header X-Forwarded-Proto http;
          proxy_set_header X-Forwarded-Prefix ${config.services.prowlarr.settings.server.urlbase};
        '';
      };
    })
  ];

  services.homepage-dashboard.services.Automation = [
    {
      Prowlarr = {
        icon = "prowlarr.png";
        href = "${config.services.prowlarr.settings.server.urlbase}/";
        description = "Indexer management behind localhost-only services.";
        weight = 60;
      };
    }
  ];

  users.groups.prowlarr = { };

  systemd.tmpfiles.rules = [ "d ${config.services.prowlarr.dataDir} 0750 prowlarr prowlarr - -" ];

  services.prowlarr = {
    enable = true;
    package = pkgs.prowlarr;
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
    Group = lib.mkForce "prowlarr";
  };
}
