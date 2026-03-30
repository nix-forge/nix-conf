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

    primaryGroup = lib.mkOption {
      type = lib.types.str;
      default = "radarr";
      description = "Primary group for Radarr service runtime.";
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

    users.users.radarr.extraGroups = lib.mkAfter [
      cfg.downloadsGroup
      cfg.mediaGroup
    ];

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 radarr ${cfg.primaryGroup} - -"
      "d ${cfg.stackRoot} 0755 root root - -"
      "d ${cfg.stackRoot}/data 0755 root root - -"
      "d ${cfg.stackRoot}/data/media 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/media/movies 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/torrents 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/data/torrents/movies 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/data/usenet 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/data/usenet/movies 2770 root ${cfg.downloadsGroup} - -"
    ];

    services.radarr = {
      enable = true;
      dataDir = cfg.stateDir;
      user = "radarr";
      group = cfg.primaryGroup;
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

    systemd.services.radarr.serviceConfig.UMask = lib.mkForce "0002";
  };
}
