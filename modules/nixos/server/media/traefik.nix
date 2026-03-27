{ config, lib, ... }:
let
  cfg = config.my.media;
  isProtectedHost = host: builtins.elem host cfg.cloudflare.accessProtectedHosts;
  mkPublicService = host: service: {
    rule =
      "Host(`${host}`)"
      + lib.optionalString (isProtectedHost host) " && HeadersRegexp(`Cf-Access-Jwt-Assertion`, `.+`)";
    entryPoints = [ "websecure" ];
    inherit service;
    tls = { };
    middlewares = [
      "default-secure-headers"
      "public-ratelimit"
    ]
    ++ lib.optionals (cfg.network.trustedProxyCidrs != [ ]) [ "cf-source-allowlist" ]
    ++ lib.optionals (cfg.cloudflare.accessAudTag != "") [ "cf-access-aud-header" ];
  };
  mkRouter = host: service: {
    entryPoints = [ "websecure" ];
    rule = "Host(`${host}`)";
    inherit service;
    middlewares = [ "default-secure-headers" ];
    tls = { };
  };
in
{
  config = lib.mkIf (cfg.enable && cfg.services.traefik.enable) {
    services.traefik = {
      enable = true;

      staticConfigOptions = {
        api.dashboard = false;

        entryPoints = {
          web = {
            address = ":${toString cfg.ports.traefikHttp}";
            http.redirections.entryPoint = {
              to = "websecure";
              scheme = "https";
            };
          }
          // lib.optionalAttrs (cfg.network.trustedProxyCidrs != [ ]) {
            forwardedHeaders.trustedIPs = cfg.network.trustedProxyCidrs;
          };
          websecure = {
            address = ":${toString cfg.ports.traefikHttps}";
          }
          // lib.optionalAttrs (cfg.network.trustedProxyCidrs != [ ]) {
            forwardedHeaders.trustedIPs = cfg.network.trustedProxyCidrs;
          };
        };

        log.level = "INFO";
      };

      dynamicConfigOptions = {
        http = {
          middlewares.default-secure-headers.headers = {
            stsSeconds = 31536000;
            stsIncludeSubdomains = true;
            stsPreload = true;
            forceSTSHeader = true;
            frameDeny = true;
            contentTypeNosniff = true;
            browserXssFilter = true;
            referrerPolicy = "strict-origin-when-cross-origin";
            customRequestHeaders.X-Forwarded-Proto = "https";
          };

          middlewares.public-ratelimit.rateLimit = {
            average = 100;
            burst = 50;
          };

          middlewares.cf-source-allowlist.ipAllowList = lib.mkIf (cfg.network.trustedProxyCidrs != [ ]) {
            sourceRange = cfg.network.trustedProxyCidrs;
            ipStrategy.depth = 1;
          };

          middlewares.cf-access-aud-header.headers.customRequestHeaders =
            lib.mkIf (cfg.cloudflare.accessAudTag != "")
              {
                "CF-Access-Aud" = cfg.cloudflare.accessAudTag;
              };

          routers = lib.mkMerge [
            (lib.optionalAttrs cfg.services.jellyfin.enable {
              jellyfin = mkRouter cfg.hosts.jellyfin "jellyfin";
              jellyfin-public = mkPublicService cfg.hosts.jellyfinPublic "jellyfin";
            })
            (lib.optionalAttrs cfg.services.jellyseerr.enable {
              jellyseerr = mkRouter cfg.hosts.jellyseerr "jellyseerr";
              jellyseerr-public = mkPublicService cfg.hosts.jellyseerrPublic "jellyseerr";
            })
            (lib.optionalAttrs cfg.services.vaultwarden.enable {
              vaultwarden = mkRouter cfg.hosts.vaultwarden "vaultwarden";
              vaultwarden-public = mkPublicService cfg.hosts.vaultwardenPublic "vaultwarden";
            })
            (lib.optionalAttrs cfg.services.arr.enable {
              radarr = mkRouter cfg.hosts.radarr "radarr";
              sonarr = mkRouter cfg.hosts.sonarr "sonarr";
              prowlarr = mkRouter cfg.hosts.prowlarr "prowlarr";
              bazarr = mkRouter cfg.hosts.bazarr "bazarr";
            })
            (lib.optionalAttrs cfg.services.torrent.enable {
              qbittorrent = mkRouter cfg.hosts.qbittorrent "qbittorrent";
              nzbget = mkRouter cfg.hosts.nzbget "nzbget";
            })
            (lib.optionalAttrs cfg.services.homebridge.enable {
              homebridge = mkRouter cfg.hosts.homebridge "homebridge";
            })
            (lib.optionalAttrs cfg.services.scrypted.enable {
              scrypted = mkRouter cfg.hosts.scrypted "scrypted";
            })
            (lib.optionalAttrs cfg.services.pihole.enable { pihole = mkRouter cfg.hosts.pihole "pihole"; })
          ];

          services = lib.mkMerge [
            (lib.optionalAttrs cfg.services.jellyfin.enable {
              jellyfin.loadBalancer.servers = [ { url = "http://127.0.0.1:${toString cfg.ports.jellyfin}"; } ];
            })
            (lib.optionalAttrs cfg.services.jellyseerr.enable {
              jellyseerr.loadBalancer.servers = [
                { url = "http://127.0.0.1:${toString cfg.ports.jellyseerr}"; }
              ];
            })
            (lib.optionalAttrs cfg.services.vaultwarden.enable {
              vaultwarden.loadBalancer.servers = [
                { url = "http://127.0.0.1:${toString cfg.ports.vaultwarden}"; }
              ];
            })
            (lib.optionalAttrs cfg.services.arr.enable {
              radarr.loadBalancer.servers = [ { url = "http://127.0.0.1:${toString cfg.ports.radarr}"; } ];
              sonarr.loadBalancer.servers = [ { url = "http://127.0.0.1:${toString cfg.ports.sonarr}"; } ];
              prowlarr.loadBalancer.servers = [ { url = "http://127.0.0.1:${toString cfg.ports.prowlarr}"; } ];
              bazarr.loadBalancer.servers = [ { url = "http://127.0.0.1:${toString cfg.ports.bazarr}"; } ];
            })
            (lib.optionalAttrs cfg.services.torrent.enable {
              qbittorrent.loadBalancer.servers = [
                { url = "http://127.0.0.1:${toString cfg.ports.qbittorrent}"; }
              ];
              nzbget.loadBalancer.servers = [ { url = "http://127.0.0.1:${toString cfg.ports.nzbget}"; } ];
            })
            (lib.optionalAttrs cfg.services.homebridge.enable {
              homebridge.loadBalancer.servers = [
                { url = "http://127.0.0.1:${toString cfg.ports.homebridge}"; }
              ];
            })
            (lib.optionalAttrs cfg.services.scrypted.enable {
              scrypted.loadBalancer.servers = [ { url = "http://127.0.0.1:${toString cfg.ports.scrypted}"; } ];
            })
            (lib.optionalAttrs cfg.services.pihole.enable {
              pihole.loadBalancer.servers = [ { url = "http://127.0.0.1:${toString cfg.ports.pihole}"; } ];
            })
          ];
        };
      };
    };
  };
}
