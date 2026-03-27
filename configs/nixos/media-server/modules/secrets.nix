{
  config,
  lib,
  secrets,
  ...
}:
let
  cfg = config.my.media;
  requiredSecretNames = [
    cfg.secrets.cloudflareDdnsToken
    cfg.secrets.vaultwardenEnv
    cfg.secrets.vpnGluetunEnv
    cfg.secrets.qbittorrentEnv
    cfg.secrets.piholeEnv
    cfg.secrets.homebridgeEnv
    cfg.secrets.scryptedEnv
  ]
  ++ lib.optionals cfg.services.cloudflared.enable [
    cfg.secrets.cloudflaredCreds
    cfg.secrets.cloudflaredCert
  ];

  mkConfiguredSecretAssertion = name: {
    assertion = name != "";
    message = "Set my.media.secrets.* in configs/nixos/media-server/modules/site.nix";
  };

  mkSelectedSecretAssertion = name: {
    assertion = builtins.hasAttr name secrets;
    message = "Secret `${name}` is not available for this host's configured secret groups";
  };
in
{
  assertions =
    map mkConfiguredSecretAssertion requiredSecretNames
    ++ map mkSelectedSecretAssertion requiredSecretNames;

  age.secrets = lib.optionalAttrs (cfg.secrets.vaultwardenEnv != "") {
    "${cfg.secrets.vaultwardenEnv}" = {
      owner = "vaultwarden";
      group = "vaultwarden";
      mode = "0400";
    };
  };
}
