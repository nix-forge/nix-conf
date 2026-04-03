{ lib, ... }:
{
  services.vaultwarden = {
    configureNginx = lib.mkDefault false;
    configurePostgres = lib.mkDefault false;
    config = {
      ROCKET_ADDRESS = lib.mkDefault "127.0.0.1";
      ROCKET_PORT = lib.mkDefault 8222;
    };
  };
}
