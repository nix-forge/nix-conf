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

    primaryGroup = lib.mkOption {
      type = lib.types.str;
      default = "lidarr";
      description = "Primary group for Lidarr service runtime.";
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

    users.users.lidarr.extraGroups = lib.mkAfter [
      cfg.downloadsGroup
      cfg.mediaGroup
    ];

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 lidarr ${cfg.primaryGroup} - -"
      "d ${cfg.stackRoot} 0755 root root - -"
      "d ${cfg.stackRoot}/data 0755 root root - -"
      "d ${cfg.stackRoot}/data/media 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/media/music 2770 root ${cfg.mediaGroup} - -"
    ];

    services.lidarr = {
      enable = true;
      dataDir = cfg.stateDir;
      user = "lidarr";
      group = cfg.primaryGroup;
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

    systemd.services.lidarr.serviceConfig.UMask = lib.mkForce "0002";
  };
}
