{ pkgs, desktop }:
let
  inherit (pkgs) lib;
  cfg = desktop.config;
  site = cfg.homelab.operations.lanHttps.sites.actual;
  host = "actual.${cfg.homelab.operations.lanHttps.domain}";
  virtualHost = cfg.services.nginx.virtualHosts.${host};
  customPort = 17506;
  customPortConfig =
    (desktop.extendModules {
      modules = [ { services.actual.settings.port = lib.mkForce customPort; } ];
    }).config;
  contracts = [
    cfg.services.actual.enable
    (cfg.services.actual.settings.loginMethod == "openid")
    cfg.services.actual.settings.enforceOpenId
    (
      cfg.services.actual.settings.openId.client_secret._secret
      == "/run/credentials/actual.service/oidc-secret"
    )
    (builtins.elem "oidc-secret:${cfg.nixSeal.secrets.homelab-actual-oidc-secret.path}" cfg.systemd.services.actual.serviceConfig.LoadCredential)
    (cfg.services.actual.settings.allowedLoginMethods == [ "openid" ])
    (cfg.services.actual.settings.openId.server_hostname == "https://${host}")
    (
      cfg.services.actual.settings.openId.discoveryURL
      == "https://identity.${cfg.homelab.operations.lanHttps.domain}/realms/actual"
    )
    (lib.hasSuffix " https://${host}" cfg.systemd.services.homelab-actual-identity.serviceConfig.ExecStart)
    (lib.assertMsg
      (
        cfg.systemd.services.actual.wantedBy == [ ]
        && builtins.elem "timers.target" cfg.systemd.timers.actual.wantedBy
        && cfg.systemd.timers.actual.timerConfig.Unit == "actual.service"
        && builtins.elem cfg.systemd.timers.actual.unitConfig.ConditionPathExists cfg.hardware.storage.encryptedRoot.backup.coldPaths
      )
      "Actual must start through the timer gated on its encrypted image, without requiring an unprovisioned vault at boot."
    )
    (builtins.elem "actual-vault-ready.service" cfg.systemd.services.actual.requires)
    (builtins.elem "homelab-actual-identity.service" cfg.systemd.services.actual.requires)
    (cfg.nixSeal.secrets.homelab-actual-password.owner == "ianmh")
    (!cfg.services.actual.openFirewall)
    (cfg.services.actual.settings.hostname == "127.0.0.1")
    (site.upstream == "http://127.0.0.1:${toString cfg.services.actual.settings.port}")
    (site.allowedCIDRs == null)
    (builtins.elem "127.0.0.0/8" cfg.homelab.operations.lanHttps.allowedCIDRs)
    (!builtins.elem "0.0.0.0/0" cfg.homelab.operations.lanHttps.allowedCIDRs)
    virtualHost.onlySSL
    (virtualHost.useACMEHost == cfg.homelab.operations.lanHttps.certificateHost)
    (virtualHost.locations."/".proxyPass == site.upstream)
    (lib.hasInfix "proxy_request_buffering off;" virtualHost.locations."/".extraConfig)
    (lib.hasInfix "proxy_buffering off;" virtualHost.locations."/".extraConfig)
    (lib.hasInfix "proxy_ignore_headers X-Accel-Buffering;" virtualHost.locations."/".extraConfig)
    (lib.hasInfix "proxy_max_temp_file_size 0;" virtualHost.locations."/".extraConfig)
    (lib.hasInfix "client_max_body_size 100m;" virtualHost.locations."/".extraConfig)
    (lib.hasInfix "deny all;" virtualHost.extraConfig)
    (!lib.hasInfix "Cross-Origin-Opener-Policy" virtualHost.extraConfig)
    (!lib.hasInfix "Cross-Origin-Embedder-Policy" virtualHost.extraConfig)
    (lib.assertMsg (lib.hasInfix "http://127.0.0.1:${toString customPort}/health" customPortConfig.systemd.services.actual.postStart) "Actual readiness must follow its configured listen port.")
  ];
in
assert lib.assertMsg (lib.all (x: x)
  contracts
) "Actual HTTPS must use the private proxy and limit first-user enrollment to the desktop.";
pkgs.runCommand "homelab-actual-https" { } "touch $out"
