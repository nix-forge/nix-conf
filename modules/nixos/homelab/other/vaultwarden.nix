{ lib, config, ... }:
{
  assertions = [
    {
      assertion = lib.hasAttrByPath [ "age" "secrets" "vaultwarden-admin-token" ] config;
      message = "age.secrets.vaultwarden-admin-token must exist when importing homelab.other.vaultwarden.";
    }
  ];

  services.vaultwarden = {
    enable = true;
    configureNginx = false;
    configurePostgres = false;
    config = {
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = 8222;
      SIGNUPS_ALLOWED = false;
    };
    environmentFile = config.age.secrets.vaultwarden-admin-token.path;
  };
}
