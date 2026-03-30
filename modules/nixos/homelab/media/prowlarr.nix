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

    sharedGroup = lib.mkOption {
      type = lib.types.str;
      default = "media";
      description = "Shared group for media stack access.";
    };

    sharedGroupGid = lib.mkOption {
      type = lib.types.int;
      default = 2000;
      description = "GID for the shared media group.";
    };
  };

  config = {
    users.groups.${cfg.sharedGroup}.gid = lib.mkDefault cfg.sharedGroupGid;

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 prowlarr ${cfg.sharedGroup} - -"
    ];

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
      environmentFiles = [ ];
    };

    systemd.services.prowlarr.serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = lib.mkForce "prowlarr";
      Group = lib.mkForce cfg.sharedGroup;
    };
  };
}
