{ config, ... }: {
  imports = [ ./config-validation.nix ];

  lib.localControl.mkLocalControlConfigs =
    { pkgs, cfg }:
    let
      inherit (pkgs) lib;
      checker = config.lib.localControl.mkLocalControlConfigChecker { inherit pkgs; };
    in
    {
      proxyConfig = pkgs.replaceVarsWith {
        name = "local-control-proxy.conf";
        src = ./config/proxy.Caddyfile.in;
        # Validate provisioning with ephemeral fixture PKI, never runtime keys.
        postCheck = ''
          ${lib.getExe checker} "$target" >/dev/null
        '';
        replacements = {
          bindAddresses =
            if cfg.bindAddress == "127.0.0.1" then cfg.bindAddress else "127.0.0.1 ${cfg.bindAddress}";
          inherit (cfg) dashboardDirectory privateHostname;
          inherit (cfg) webPort apiPort proxyPort;
        };
      };

      serverCertificateExtensions = pkgs.writeText "local-control-server-extensions" (
        lib.generators.toINIWithGlobalSection { } {
          globalSection = {
            basicConstraints = "critical,CA:FALSE";
            keyUsage = "critical,digitalSignature,keyEncipherment";
            extendedKeyUsage = "serverAuth";
            subjectAltName = "DNS:${cfg.privateHostname},IP:${cfg.bindAddress}";
          };
        }
      );

      clientCertificateExtensions = pkgs.writeText "local-control-client-extensions" (
        lib.generators.toINIWithGlobalSection { } {
          globalSection = {
            basicConstraints = "critical,CA:FALSE";
            keyUsage = "critical,digitalSignature,keyEncipherment";
            extendedKeyUsage = "clientAuth";
          };
        }
      );
    };
}
