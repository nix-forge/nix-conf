{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.caddy;
  inherit (config.security.acme) certs;

  mkVHostConf =
    hostOpts:
    let
      sslCertDir = if hostOpts.useACMEHost == null then null else certs.${hostOpts.useACMEHost}.directory;
    in
    ''
      ${hostOpts.hostName} ${lib.concatStringsSep " " hostOpts.serverAliases} {
        ${lib.optionalString (
          hostOpts.listenAddresses != [ ]
        ) "bind ${lib.concatStringsSep " " hostOpts.listenAddresses}"}
        ${lib.optionalString (
          hostOpts.useACMEHost != null
        ) "tls ${sslCertDir}/cert.pem ${sslCertDir}/key.pem"}
        ${lib.optionalString (hostOpts.logFormat != null) ''
          log {
            ${hostOpts.logFormat}
          }
        ''}

        ${hostOpts.extraConfig}
      }
    '';

  generatedCaddyfile = pkgs.writeText "Caddyfile" ''
    {
      ${cfg.globalConfig}
    }
    ${cfg.extraConfig}
    ${lib.concatMapStringsSep "\n" mkVHostConf (lib.attrValues cfg.virtualHosts)}
  '';
in
{
  services.caddy = {
    # Use an unformatted generated Caddyfile to avoid nixpkgs' Caddyfile-formatted
    # runCommand, which fails on this host when cp tries to chmod in /nix/store.
    configFile = lib.mkDefault generatedCaddyfile;
  };
}
