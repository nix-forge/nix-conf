{ lib, config, ... }:
{
  security.acme = {
    acceptTerms = lib.mkDefault true;
    defaults = {
      reloadServices = lib.mkIf config.services.caddy.enable [ "caddy.service" ];
    };
  };
}
