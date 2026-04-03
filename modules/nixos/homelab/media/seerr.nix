{ lib, config, ... }:
{
  config = {
    services.seerr = {
      port = lib.mkDefault 5055;
      openFirewall = lib.mkDefault false;
    };

    users.groups.seerr = lib.mkIf config.services.seerr.enable { };
    users.users.seerr = lib.mkIf config.services.seerr.enable {
      isSystemUser = true;
      group = "seerr";
    };

    systemd.tmpfiles.rules = lib.mkIf config.services.seerr.enable [
      "d ${config.services.seerr.configDir} 0750 seerr seerr - -"
    ];

    systemd.services.seerr.serviceConfig = lib.mkIf config.services.seerr.enable {
      DynamicUser = lib.mkForce false;
      User = lib.mkForce "seerr";
      Group = lib.mkForce "seerr";
    };
  };
}
