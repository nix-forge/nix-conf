{
  lib,
  pkgs,
  config,
  ...
}:
{
  config = {
    services.flaresolverr = {
      package = lib.mkDefault pkgs.flaresolverr;
      port = lib.mkDefault 8191;
      openFirewall = lib.mkDefault false;
    };

    users.groups.flaresolverr = lib.mkIf config.services.flaresolverr.enable { };
    users.users.flaresolverr = lib.mkIf config.services.flaresolverr.enable {
      isSystemUser = true;
      group = "flaresolverr";
    };

    systemd.tmpfiles.rules = lib.mkIf config.services.flaresolverr.enable [
      "d /var/lib/flaresolverr 0750 flaresolverr flaresolverr - -"
    ];

    systemd.services.flaresolverr.serviceConfig = lib.mkIf config.services.flaresolverr.enable {
      User = lib.mkForce "flaresolverr";
      Group = lib.mkForce "flaresolverr";
    };
  };
}
