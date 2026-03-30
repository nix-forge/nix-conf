{ lib, config, ... }:
let
  cfg = config.homelab.media.jellyfin;
in
{
  options.homelab.media.jellyfin = {
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/jellyfin";
      description = "Jellyfin state directory.";
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
      "d ${cfg.stateDir} 0750 jellyfin ${cfg.sharedGroup} - -"
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
      "d ${cfg.stackRoot}/cache 2770 root ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot}/cache/jellyfin 2770 root ${cfg.sharedGroup} - -"
    ];

    services.jellyfin = {
      enable = true;
      user = "jellyfin";
      group = cfg.sharedGroup;
      dataDir = cfg.stateDir;
      openFirewall = false;
    };

    users.users.jellyfin.extraGroups = [ cfg.sharedGroup ];
  };
}
