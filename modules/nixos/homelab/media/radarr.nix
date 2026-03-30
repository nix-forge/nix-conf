{ lib, config, ... }:
let
  cfg = config.homelab.media.radarr;
in
{
  options.homelab.media.radarr = {
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/radarr";
      description = "Radarr state directory.";
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
      "d ${cfg.stateDir} 0750 radarr ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot} 0755 root root - -"
      "d ${cfg.stackRoot}/data 2770 root ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot}/data/media 2770 root ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot}/data/media/movies 2770 root ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot}/data/torrents 2770 root ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot}/data/torrents/movies 2770 root ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot}/data/usenet 2770 root ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot}/data/usenet/movies 2770 root ${cfg.sharedGroup} - -"
    ];

    services.radarr = {
      enable = true;
      dataDir = cfg.stateDir;
      user = "radarr";
      group = cfg.sharedGroup;
      openFirewall = false;
      settings = {
        server = {
          port = 7878;
          bindaddress = "127.0.0.1";
          urlbase = "/radarr";
        };
      };
      environmentFiles = [ ];
    };
  };
}
