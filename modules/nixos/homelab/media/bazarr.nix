{ lib, config, ... }:
let
  cfg = config.homelab.media.bazarr;
in
{
  options.homelab.media.bazarr = {
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/bazarr";
      description = "Bazarr state directory.";
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
      "d ${cfg.stateDir} 0750 bazarr ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot} 0755 root root - -"
      "d ${cfg.stackRoot}/data 2770 root ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot}/data/media 2770 root ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot}/data/media/movies 2770 root ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot}/data/media/tv 2770 root ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot}/data/media/music 2770 root ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot}/data/media/books 2770 root ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot}/data/media/books/books 2770 root ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot}/data/media/books/audiobooks 2770 root ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot}/data/media/books/comics 2770 root ${cfg.sharedGroup} - -"
    ];

    services.bazarr = {
      enable = true;
      dataDir = cfg.stateDir;
      user = "bazarr";
      group = cfg.sharedGroup;
      listenPort = 6767;
      openFirewall = false;
    };
  };
}
