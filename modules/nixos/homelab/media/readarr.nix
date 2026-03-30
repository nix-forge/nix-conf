{ lib, config, ... }:
let
  cfg = config.homelab.media.readarr;
in
{
  options.homelab.media.readarr = {
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/readarr";
      description = "Readarr state directory.";
    };

    stackRoot = lib.mkOption {
      type = lib.types.str;
      default = "/srv/media-stack";
      description = "Shared media stack root.";
    };

    primaryGroup = lib.mkOption {
      type = lib.types.str;
      default = "readarr";
      description = "Primary group for Readarr service runtime.";
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

    users.users.readarr.extraGroups = lib.mkAfter [
      cfg.downloadsGroup
      cfg.mediaGroup
    ];

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 readarr ${cfg.primaryGroup} - -"
      "d ${cfg.stackRoot} 0755 root root - -"
      "d ${cfg.stackRoot}/data 0755 root root - -"
      "d ${cfg.stackRoot}/data/media 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/media/books 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/media/books/books 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/media/books/audiobooks 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/media/books/comics 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/torrents 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/data/torrents/books 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/data/usenet 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/data/usenet/books 2770 root ${cfg.downloadsGroup} - -"
    ];

    services.readarr = {
      enable = true;
      dataDir = cfg.stateDir;
      user = "readarr";
      group = cfg.primaryGroup;
      openFirewall = false;
      settings = {
        server = {
          port = 8787;
          bindaddress = "127.0.0.1";
          urlbase = "/readarr";
        };
      };
      environmentFiles = [ ];
    };

    systemd.services.readarr.serviceConfig.UMask = lib.mkForce "0002";
  };
}
