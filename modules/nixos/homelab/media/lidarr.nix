{ lib, config, ... }:
let
  cfg = config.homelab.media.lidarr;
in
{
  options.homelab.media.lidarr = {
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/lidarr";
      description = "Lidarr state directory.";
    };

    stackRoot = lib.mkOption {
      type = lib.types.str;
      default = "/srv/media-stack";
      description = "Shared media stack root.";
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
      "d ${cfg.stateDir} 0750 lidarr ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot} 0755 root root - -"
      "d ${cfg.stackRoot}/data 2770 root ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot}/data/media 2770 root ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot}/data/media/music 2770 root ${cfg.sharedGroup} - -"
    ];

    services.lidarr = {
      enable = true;
      dataDir = cfg.stateDir;
      user = "lidarr";
      group = cfg.sharedGroup;
      openFirewall = false;
      settings = {
        server = {
          port = 8686;
          bindaddress = "127.0.0.1";
          urlbase = "/lidarr";
        };
      };
      environmentFiles = [ ];
    };
  };
}
