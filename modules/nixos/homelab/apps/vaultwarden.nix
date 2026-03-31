{ lib, config, ... }:
{
  assertions = [
    {
      assertion = lib.hasAttrByPath [ "age" "secrets" "vaultwarden-admin-token" ] config;
      message = "age.secrets.vaultwarden-admin-token must exist when importing homelab.apps.vaultwarden.";
    }
  ];

  services.nginx.virtualHosts."_".locations = {
    "= /vaultwarden" = {
      return = "302 /vaultwarden/";
    };
    "/vaultwarden/" = {
      proxyPass = "http://${config.services.vaultwarden.config.ROCKET_ADDRESS}:${toString config.services.vaultwarden.config.SIGNUPS_ALLOWED}/";
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
        proxy_set_header X-Forwarded-Prefix /vaultwarden;
        proxy_buffering off;
      '';
    };
  };

  services.homepage-dashboard.services.Apps = [
    {
      Vaultwarden = {
        icon = "vaultwarden.png";
        href = "/vaultwarden/";
        description = "Password vault administration and client access over Tailscale.";
        weight = 10;
      };
    }
  ];

  services.vaultwarden = {
    enable = true;
    configureNginx = false;
    configurePostgres = false;
    config = {
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = 8222;
      SIGNUPS_ALLOWED = false;
    };
    environmentFile = config.age.secrets.vaultwarden-admin-token.path;
  };
}
