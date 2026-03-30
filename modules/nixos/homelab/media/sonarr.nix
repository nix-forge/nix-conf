{ lib, config, ... }:
let
  cfg = config.homelab.media.sonarr;
in
{
  options.homelab.media.sonarr = {
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/sonarr";
      description = "Sonarr state directory.";
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
      "d ${cfg.stateDir} 0750 sonarr ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot} 0755 root root - -"
      "d ${cfg.stackRoot}/data 2770 root ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot}/data/media 2770 root ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot}/data/media/tv 2770 root ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot}/data/torrents 2770 root ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot}/data/torrents/tv 2770 root ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot}/data/usenet 2770 root ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot}/data/usenet/tv 2770 root ${cfg.sharedGroup} - -"
    ];

    services.sonarr = {
      enable = true;
      dataDir = cfg.stateDir;
      user = "sonarr";
      group = cfg.sharedGroup;
      openFirewall = false;
      settings = {
        server = {
          port = 8989;
          bindaddress = "127.0.0.1";
          urlbase = "/sonarr";
        };
      };
      environmentFiles = [ ];
    };
  };
}
