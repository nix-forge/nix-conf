{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.homelab.media.prowlarr;
in
{
  options.homelab.media.prowlarr = {
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/prowlarr";
      description = "Prowlarr state directory.";
    };

    primaryGroup = lib.mkOption {
      type = lib.types.str;
      default = "prowlarr";
      description = "Primary group for Prowlarr service runtime.";
    };
  };

  config = {
    users.groups.${cfg.primaryGroup} = { };

    systemd.tmpfiles.rules = [ "d ${cfg.stateDir} 0750 prowlarr ${cfg.primaryGroup} - -" ];

    services.prowlarr = {
      enable = true;
      package = pkgs.prowlarr;
      dataDir = cfg.stateDir;
      openFirewall = false;
      settings = {
        server = {
          port = 9696;
          bindaddress = "127.0.0.1";
          urlbase = "/prowlarr";
        };
      };
    };

    systemd.services.prowlarr.serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = lib.mkForce "prowlarr";
      Group = lib.mkForce cfg.primaryGroup;
    };
  };
}
