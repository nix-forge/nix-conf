{ lib, pkgs, ... }:
{
  config = {
    users.groups.flaresolverr = { };
    users.users.flaresolverr = {
      isSystemUser = true;
      group = "flaresolverr";
    };

    systemd.tmpfiles.rules = [ "d /var/lib/flaresolverr 0750 flaresolverr flaresolverr - -" ];

    services.flaresolverr = {
      enable = true;
      package = pkgs.flaresolverr;
      port = 8191;
      openFirewall = false;
    };

    systemd.services.flaresolverr.serviceConfig = {
      User = lib.mkForce "flaresolverr";
      Group = lib.mkForce "flaresolverr";
    };
  };
}
