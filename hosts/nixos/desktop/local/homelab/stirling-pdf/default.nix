{
  config,
  lib,
  pkgs,
  ...
}:
let
  port = 18083;
  url = "https://pdf.${config.homelab.operations.lanHttps.domain}";
in
{
  nixSeal.secrets.homelab-stirling-admin-password.phase = "services";
  nixSeal.secrets.homelab-stirling-admin-username = {
    phase = "services";
  };
  nixSeal.templates.homelab-stirling-admin-env = {
    content = ''
      SECURITY_INITIALLOGIN_USERNAME={{nix-seal:homelab-stirling-admin-username}}
      SECURITY_INITIALLOGIN_PASSWORD={{nix-seal:homelab-stirling-admin-password}}
    '';
    phase = "services";
  };

  services.stirling-pdf = {
    enable = true;
    package = pkgs.stirling-pdf;
    environmentFiles = [ config.nixSeal.templates.homelab-stirling-admin-env.path ];
    environment = {
      SERVER_ADDRESS = "127.0.0.1";
      SERVER_PORT = port;
      SECURITY_ENABLELOGIN = true;
      SYSTEM_FRONTENDURL = url;
      SYSTEM_CORSALLOWEDORIGINS = url;
      SYSTEM_DEFAULTLOCALE = "en-US";
      SYSTEM_GOOGLEVISIBILITY = false;
      SYSTEM_ENABLEANALYTICS = false;
      SYSTEM_TEMPFILEMANAGEMENT_MAXAGEHOURS = 2;
      SYSTEM_TEMPFILEMANAGEMENT_CLEANUPINTERVALMINUTES = 15;
      SYSTEMFILEUPLOADLIMIT = "100MB";
      STIRLING_BILLING_ACCOUNT_LINK_ENABLED = false;
      AIENGINE_CLOUDDOCUMENTINDEXING = false;
      SPRINGDOC_API_DOCS_ENABLED = false;
      SPRINGDOC_SWAGGER_UI_ENABLED = false;
      JAVA_TOOL_OPTIONS = lib.concatStringsSep " " (
        (config.lib.desktopJavaMemory.flags "stirling-pdf")
        ++ [
          "-Xmx1536m"
          # systemd mounts DynamicUser state/cache directories noexec. PDFium's
          # verified native cache must live on the private executable runtime mount.
          "-Djpdfium.native.cacheDir=/run/stirling-pdf/jpdfium"
          # These upstream classes log search terms, matching text or filenames.
          "-Dlogging.level.stirling.software.SPDF.controller.api.security=OFF"
        ]
      );
    };
  };

  systemd.services = {
    stirling-pdf = {
      requires = [ "nix-seal-activate.service" ];
      after = [ "nix-seal-activate.service" ];
      serviceConfig = {
        StateDirectoryMode = "0700";
        RuntimeDirectoryMode = "0700";
        PrivateTmp = true;
        ProtectSystem = "strict";
        Restart = "on-failure";
        RestartSec = 10;
        MemoryMax = "3G";
        LimitCORE = 0;
        CPUQuota = "200%";
        TasksMax = 256;
        IPAddressDeny = "any";
        IPAddressAllow = [
          "127.0.0.0/8"
          "::1/128"
        ];
      };
    };
  };

  homelab.operations = {
    lanHttps.sites.pdf.upstream = "http://127.0.0.1:${toString port}";
    endpoints.pdf = {
      inherit url;
      healthUrl = "http://127.0.0.1:${toString port}/api/v1/info/status";
      description = "Private PDF editor, converter and OCR tools";
    };
    state.stirling-pdf = {
      paths = [ "/var/lib/stirling-pdf" ];
      units = [ "stirling-pdf.service" ];
    };
  };

  # PDF imports and downloads can exceed nginx's default upload limit. Stream
  # them through the proxy so private documents do not enter its disk buffers.
  services.nginx.virtualHosts."pdf.${config.homelab.operations.lanHttps.domain}" = {
    locations."/".extraConfig = lib.mkAfter ''
      client_max_body_size 100m;
      proxy_request_buffering off;
      proxy_buffering off;
      proxy_max_temp_file_size 0;
    '';
    # Uploaded documents must not enter browser HTTP caches or be sent by
    # application scripts to a remote endpoint. Browser IndexedDB is separate.
    extraConfig = lib.mkAfter ''
      add_header Cache-Control "no-store" always;
      add_header Referrer-Policy "no-referrer" always;
      add_header Content-Security-Policy "connect-src 'self' blob: data: wss://pdf.${config.homelab.operations.lanHttps.domain}; form-action 'self'; frame-ancestors 'none'" always;
    '';
  };

  assertions = [
    {
      assertion =
        config.services.stirling-pdf.environment.SERVER_ADDRESS == "127.0.0.1"
        && config.services.stirling-pdf.environment.SECURITY_ENABLELOGIN
        && config.services.stirling-pdf.environment.SYSTEM_ENABLEANALYTICS == false
        && config.services.stirling-pdf.environment.STIRLING_BILLING_ACCOUNT_LINK_ENABLED == false;
      message = "The desktop Stirling PDF service must keep login enabled and listen only on loopback.";
    }
    {
      assertion = port != config.homelab.optional.reactflux.port;
      message = "Stirling PDF and the news frontend must use different loopback ports.";
    }
  ];
}
