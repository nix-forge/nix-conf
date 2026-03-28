{ lib, pkgs, ... }:
let
  certDir = "/var/lib/tailscale-cert";

  commonProxyConfig = prefix: ''
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-Prefix ${prefix};
    proxy_http_version 1.1;
  '';

  mkPrefixLocations =
    {
      prefix,
      upstream,
      proxyWebsockets ? true,
      stripPrefix ? false,
      extraConfig ? "",
    }:
    {
      "= ${prefix}" = {
        return = "302 ${prefix}/";
      };
      "${prefix}/" = {
        proxyPass = if stripPrefix then "${upstream}/" else upstream;
        recommendedProxySettings = true;
        inherit proxyWebsockets;
        extraConfig = commonProxyConfig prefix + extraConfig;
      };
    };

  appLocations =
    mkPrefixLocations {
      prefix = "/jellyfin";
      upstream = "http://127.0.0.1:8096";
      extraConfig = ''
        proxy_buffering off;
      '';
    }
    // mkPrefixLocations {
      prefix = "/jellyseerr";
      upstream = "http://127.0.0.1:5055";
      stripPrefix = true;
      extraConfig = ''
        proxy_set_header Accept-Encoding "";
        sub_filter_once off;
        sub_filter_types text/html application/javascript text/javascript text/css;
        sub_filter 'href="/' 'href="/jellyseerr/';
        sub_filter 'src="/' 'src="/jellyseerr/';
        sub_filter 'content="/' 'content="/jellyseerr/';
        sub_filter 'url(/' 'url(/jellyseerr/';
        sub_filter '"/_next/' '"/jellyseerr/_next/';
        sub_filter "'/_next/" "'/jellyseerr/_next/";
        proxy_redirect ~^(/.*)$ /jellyseerr$1;
      '';
    }
    // mkPrefixLocations {
      prefix = "/sonarr";
      upstream = "http://127.0.0.1:8989";
    }
    // mkPrefixLocations {
      prefix = "/radarr";
      upstream = "http://127.0.0.1:7878";
    }
    // mkPrefixLocations {
      prefix = "/lidarr";
      upstream = "http://127.0.0.1:8686";
    }
    // mkPrefixLocations {
      prefix = "/readarr";
      upstream = "http://127.0.0.1:8787";
    }
    // mkPrefixLocations {
      prefix = "/bazarr";
      upstream = "http://127.0.0.1:6767";
    }
    // mkPrefixLocations {
      prefix = "/prowlarr";
      upstream = "http://127.0.0.1:9696";
    }
    // mkPrefixLocations {
      prefix = "/qbittorrent";
      upstream = "http://127.0.0.1:8081";
      extraConfig = ''
        rewrite ^/qbittorrent(.*)$ $1 break;
        proxy_set_header Referer "";
        proxy_set_header Host $proxy_host;
        proxy_cookie_path / "/; Secure";
      '';
    }
    // mkPrefixLocations {
      prefix = "/nzbget";
      upstream = "http://127.0.0.1:6789";
    }
    // mkPrefixLocations {
      prefix = "/vaultwarden";
      upstream = "http://127.0.0.1:8222";
      extraConfig = ''
        proxy_buffering off;
      '';
    }
    // mkPrefixLocations {
      prefix = "/frigate";
      upstream = "http://127.0.0.1:5000";
      extraConfig = ''
        proxy_buffering off;
      '';
    };
in
{
  services.nginx = {
    enable = true;
    package = pkgs.nginxMainline;
    enableReload = true;
    recommendedBrotliSettings = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    commonHttpConfig = ''
      access_log syslog:server=unix:/dev/log;
    '';
    virtualHosts."_" = {
      default = true;
      forceSSL = false;
      enableACME = false;
      sslCertificate = "${certDir}/cert.pem";
      sslCertificateKey = "${certDir}/key.pem";
      listen = [
        {
          addr = "0.0.0.0";
          port = 443;
          ssl = true;
        }
        {
          addr = "[::]";
          port = 443;
          ssl = true;
        }
      ];
      locations = {
        "/" = {
          proxyPass = "http://127.0.0.1:8082/";
          recommendedProxySettings = true;
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host 127.0.0.1:8082;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Proto https;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_http_version 1.1;
          '';
        };
      }
      // appLocations;
    };
  };
}
