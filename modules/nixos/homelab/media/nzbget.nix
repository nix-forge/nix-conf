{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.homelab.media.nzbget;
in
{
  options.homelab.media.nzbget = {
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/nzbget";
      description = "NZBGet state directory.";
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
      "d ${cfg.stateDir} 0750 nzbget ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot} 0755 root root - -"
      "d ${cfg.stackRoot}/data 2770 root ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot}/data/usenet 2770 root ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot}/data/usenet/incomplete 2770 root ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot}/data/usenet/movies 2770 root ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot}/data/usenet/tv 2770 root ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot}/data/usenet/music 2770 root ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot}/data/usenet/books 2770 root ${cfg.sharedGroup} - -"
    ];

    services.nzbget = {
      enable = true;
      package = pkgs.nzbget;
      user = "nzbget";
      group = cfg.sharedGroup;
      settings = {
        ControlIP = "127.0.0.1";
        ControlPort = 6789;
      };
    };

  };
}
