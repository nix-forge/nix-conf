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

    primaryGroup = lib.mkOption {
      type = lib.types.str;
      default = "bazarr";
      description = "Primary group for Bazarr service runtime.";
    };

    downloadsGroup = lib.mkOption {
      type = lib.types.str;
      default = "downloads";
      description = "Shared downloads group for media ingest workflow.";
    };

    mediaGroup = lib.mkOption {
      type = lib.types.str;
      default = "media";
      description = "Shared media library group.";
    };
  };

  config = {
    users.groups.${cfg.primaryGroup} = { };
    users.groups.${cfg.downloadsGroup} = { };
    users.groups.${cfg.mediaGroup} = { };

    users.users.bazarr.extraGroups = lib.mkAfter [
      cfg.downloadsGroup
      cfg.mediaGroup
    ];

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 bazarr ${cfg.primaryGroup} - -"
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
    ];

    services.bazarr = {
      enable = true;
      dataDir = cfg.stateDir;
      user = "bazarr";
      group = cfg.primaryGroup;
      listenPort = 6767;
      openFirewall = false;
    };

    systemd.services.bazarr.serviceConfig.UMask = lib.mkForce "0002";
  };
}
