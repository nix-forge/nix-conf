{ config, lib, ... }:
let
  cfg = config.my.media;
in
{
  config = lib.mkIf (cfg.enable && cfg.services.cloudflared.enable) {
    services.cloudflared = {
      enable = true;
      certificateFile = config.age.secrets.${cfg.secrets.cloudflaredCert}.path;
      tunnels.${cfg.cloudflare.tunnelId} = {
        credentialsFile = config.age.secrets.${cfg.secrets.cloudflaredCreds}.path;
        ingress = {
          ${cfg.hosts.vaultwardenPublic} = "https://127.0.0.1:${toString cfg.ports.traefikHttps}";
          ${cfg.hosts.jellyfinPublic} = "https://127.0.0.1:${toString cfg.ports.traefikHttps}";
          ${cfg.hosts.jellyseerrPublic} = "https://127.0.0.1:${toString cfg.ports.traefikHttps}";
        };
        default = "http_status:404";
      };
    };

    assertions = [
      {
        assertion = cfg.cloudflare.tunnelId != "";
        message = "Set my.media.cloudflare.tunnelId in configs/nixos/media-server/modules/site.nix";
      }
      {
        assertion = cfg.cloudflare.accessAudTag != "";
        message = "Set my.media.cloudflare.accessAudTag in configs/nixos/media-server/modules/site.nix";
      }
      {
        assertion = cfg.cloudflare.accessProtectedHosts != [ ];
        message = "Set my.media.cloudflare.accessProtectedHosts in configs/nixos/media-server/modules/site.nix";
      }
      {
        assertion = builtins.all (host: host != "") cfg.cloudflare.accessProtectedHosts;
        message = "All my.media.cloudflare.accessProtectedHosts entries must be non-empty";
      }
      {
        assertion = builtins.all (host: host != "") [
          cfg.hosts.vaultwardenPublic
          cfg.hosts.jellyfinPublic
          cfg.hosts.jellyseerrPublic
        ];
        message = "Set my.media.hosts.*Public values in configs/nixos/media-server/modules/site.nix";
      }
    ];

    services.fail2ban.enable = true;
    services.fail2ban.jails = {
      traefik-auth = ''
        enabled = true
        filter = traefik-auth
        action = nftables-multiport[name=traefik-auth, port="${toString cfg.ports.traefikHttps}", protocol=tcp]
        logpath = /var/log/traefik/traefik.log
        maxretry = 8
        findtime = 10m
        bantime = 12h
      '';
    };

    environment.etc."fail2ban/filter.d/traefik-auth.conf".text = ''
      [Definition]
      failregex = ^.*\"ClientAddr\":\"<HOST>:.*\"DownstreamStatus\":401.*$
                  ^.*\"ClientAddr\":\"<HOST>:.*\"DownstreamStatus\":403.*$
    '';
  };
}
