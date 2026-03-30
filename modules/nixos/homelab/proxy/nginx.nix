{ config, pkgs, ... }:
let
  certDir = "/var/lib/tailscale-cert";

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
  config = {
    services.tailscaleAuth.enable = true;

    users.users.${config.services.nginx.user}.extraGroups = [ config.services.tailscaleAuth.group ];

    services.nginx = {
      enable = true;
      package = pkgs.nginxMainline;
      enableReload = true;
      recommendedBrotliSettings = true;
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = false;
      recommendedTlsSettings = true;
      statusPage = true;
      commonHttpConfig = ''
        access_log syslog:server=unix:/dev/log;
      '';
      virtualHosts."_" = {
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
        locations =
          mkHealthzLocation
          // {
            "= /_tailscale-auth" = {
              extraConfig = ''
                internal;
                proxy_pass http://unix:${config.services.tailscaleAuth.socketPath};
                proxy_pass_request_body off;
                proxy_set_header Host $host;
                proxy_set_header Remote-Addr $remote_addr;
                proxy_set_header Remote-Port $remote_port;
                proxy_set_header Original-URI $request_uri;
                proxy_set_header X-Scheme $scheme;
                proxy_set_header X-Auth-Request-Redirect $scheme://$host$request_uri;
              '';
            };
          }
          // mkHomepageLocation "https";
      };
    };
  };
}
