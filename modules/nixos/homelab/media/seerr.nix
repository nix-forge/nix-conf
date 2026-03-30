{ lib, config, ... }:
let
  cfg = config.homelab.media.seerr;
in
{
  options.homelab.media.seerr = {
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/seerr";
      description = "Seerr state directory.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "seerr";
      description = "Seerr service user.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "seerr";
      description = "Seerr service group.";
    };
  };

  config = {
    services.seerr = {
      enable = true;
      port = 5055;
      openFirewall = false;
    };

    users.groups.${cfg.group} = { };
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 ${cfg.user} ${cfg.group} - -"
    ];

    systemd.services.seerr.serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = lib.mkForce cfg.user;
      Group = lib.mkForce cfg.group;
    };
  };
}
