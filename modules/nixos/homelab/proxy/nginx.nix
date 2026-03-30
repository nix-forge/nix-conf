{
  config,
  lib,
  pkgs,
  ...
}:
let
  certDir = "/var/lib/tailscale-cert";

  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  commonProxyConfig = prefix: forwardedProto: ''
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Proto ${forwardedProto};
    proxy_set_header X-Forwarded-Prefix ${prefix};
  '';

  mkPrefixLocations =
    {
      prefix,
      upstream,
      forwardedProto,
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
        extraConfig = commonProxyConfig prefix forwardedProto + extraConfig;
      };
    };

  mkAppLocations =
    forwardedProto: secureCookies:
    mkPrefixLocations {
      prefix = "/jellyfin";
      upstream = "http://127.0.0.1:8096";
      inherit forwardedProto;
      stripPrefix = true;
      extraConfig = ''
        proxy_buffering off;
      '';
    }
    // mkPrefixLocations {
      prefix = "/seerr";
      upstream = "http://127.0.0.1:5055";
      inherit forwardedProto;
      stripPrefix = true;
      extraConfig = ''
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
    }
    // mkPrefixLocations {
      prefix = "/sonarr";
      upstream = "http://127.0.0.1:8989";
      inherit forwardedProto;
    }
    // mkPrefixLocations {
      prefix = "/radarr";
      upstream = "http://127.0.0.1:7878";
      inherit forwardedProto;
    }
    // mkPrefixLocations {
      prefix = "/lidarr";
      upstream = "http://127.0.0.1:8686";
      inherit forwardedProto;
    }
    // mkPrefixLocations {
      prefix = "/readarr";
      upstream = "http://127.0.0.1:8787";
      inherit forwardedProto;
    }
    // mkPrefixLocations {
      prefix = "/bazarr";
      upstream = "http://127.0.0.1:6767";
      inherit forwardedProto;
    }
    // mkPrefixLocations {
      prefix = "/prowlarr";
      upstream = "http://127.0.0.1:9696";
      inherit forwardedProto;
    }
    // mkPrefixLocations {
      prefix = "/qbittorrent";
      upstream = "http://127.0.0.1:8081";
      inherit forwardedProto;
      extraConfig = ''
        rewrite ^/qbittorrent(.*)$ $1 break;
        proxy_set_header Referer "";
        proxy_set_header Host $proxy_host;
        proxy_cookie_path / "/${if secureCookies then "; Secure" else ""}";
      '';
    }
    // mkPrefixLocations {
      prefix = "/nzbget";
      upstream = "http://127.0.0.1:6789";
      inherit forwardedProto;
    }
    // mkPrefixLocations {
      prefix = "/vaultwarden";
      upstream = "http://127.0.0.1:8000";
      inherit forwardedProto;
      stripPrefix = true;
      extraConfig = ''
        proxy_buffering off;
      '';
    }
    // mkPrefixLocations {
      prefix = "/frigate";
      upstream = "http://127.0.0.1:5000";
      inherit forwardedProto;
      extraConfig = ''
        proxy_buffering off;
      '';
    };

  mkHomepageLocation = forwardedProto: {
    "/" = {
      proxyPass = "http://127.0.0.1:8082/";
      recommendedProxySettings = true;
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Host 127.0.0.1:8082;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Proto ${forwardedProto};
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      '';
    };
  };

  mkHealthzLocation = {
    "= /healthz" = {
      return = "200 ok\n";
      extraConfig = ''
        access_log off;
        default_type text/plain;
      '';
    };
  };
in
{
  options.homelab.proxy.vmHttpAccess = {
    enable = mkEnableOption "a VM-only HTTP listener for local browser testing";

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Guest HTTP port exposed for local VM browser testing.";
    };
  };

  options.homelab.proxy.tailscaleTls.enable = mkOption {
    type = types.bool;
    default = true;
    description = "Whether to expose the main nginx vhost with Tailscale-managed TLS certificates.";
  };

  config = {
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
      virtualHosts."_" = mkIf config.homelab.proxy.tailscaleTls.enable {
        default = true;
        addSSL = true;
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
        locations = mkHealthzLocation // mkHomepageLocation "https" // mkAppLocations "https" true;
      };
    };

    services.nginx.virtualHosts.vm-http = mkIf config.homelab.proxy.vmHttpAccess.enable {
      serverName = "_";
      listen = [
        {
          addr = "0.0.0.0";
          inherit (config.homelab.proxy.vmHttpAccess) port;
        }
        {
          addr = "[::]";
          inherit (config.homelab.proxy.vmHttpAccess) port;
        }
      ];
      locations = mkHealthzLocation // mkHomepageLocation "http" // mkAppLocations "http" false;
    };
  };
}
