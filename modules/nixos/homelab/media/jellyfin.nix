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

    primaryGroup = lib.mkOption {
      type = lib.types.str;
      default = "jellyfin";
      description = "Primary group for Jellyfin service runtime.";
    };

    mediaGroup = lib.mkOption {
      type = lib.types.str;
      default = "media";
      description = "Shared media library group.";
    };
  };

  config = {
    users.groups.${cfg.primaryGroup} = { };
    users.groups.${cfg.mediaGroup} = { };

    users.users.jellyfin.extraGroups = lib.mkAfter [ cfg.mediaGroup ];

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 jellyfin ${cfg.primaryGroup} - -"
      "d ${cfg.stackRoot} 0755 root root - -"
      "d ${cfg.stackRoot}/data 0755 root root - -"
      "d ${cfg.stackRoot}/data/media 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/media/movies 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/media/tv 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/media/music 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/media/books 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/media/books/books 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/media/books/audiobooks 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/media/books/comics 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/cache 0755 root root - -"
      "d ${cfg.stackRoot}/cache/jellyfin 2750 jellyfin ${cfg.primaryGroup} - -"
    ];

    services.jellyfin = {
      enable = true;
      user = "jellyfin";
      group = cfg.primaryGroup;
      dataDir = cfg.stateDir;
      openFirewall = false;
    };
  };
}
