{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.homelab.media.flaresolverr;
in
{
  options.homelab.media.flaresolverr = {
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/flaresolverr";
      description = "FlareSolverr state directory.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "flaresolverr";
      description = "FlareSolverr service user.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "flaresolverr";
      description = "FlareSolverr service group.";
    };
  };

  config = {
    users.groups.${cfg.group} = { };
    users.users.${cfg.user} = {
      isSystemUser = true;
      inherit (cfg) group;
    };

    systemd.tmpfiles.rules = [ "d ${cfg.stateDir} 0750 ${cfg.user} ${cfg.group} - -" ];

    services.flaresolverr = {
      enable = true;
      package = pkgs.flaresolverr;
      port = 8191;
      openFirewall = false;
    };

    systemd.services.flaresolverr.serviceConfig = {
      User = lib.mkForce cfg.user;
      Group = lib.mkForce cfg.group;
    };
  };
}
