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

    primaryGroup = lib.mkOption {
      type = lib.types.str;
      default = "sonarr";
      description = "Primary group for Sonarr service runtime.";
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

    users.users.sonarr.extraGroups = lib.mkAfter [
      cfg.downloadsGroup
      cfg.mediaGroup
    ];

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 sonarr ${cfg.primaryGroup} - -"
      "d ${cfg.stackRoot} 0755 root root - -"
      "d ${cfg.stackRoot}/data 0755 root root - -"
      "d ${cfg.stackRoot}/data/media 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/media/tv 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/torrents 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/data/torrents/tv 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/data/usenet 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/data/usenet/tv 2770 root ${cfg.downloadsGroup} - -"
    ];

    services.sonarr = {
      enable = true;
      dataDir = cfg.stateDir;
      user = "sonarr";
      group = cfg.primaryGroup;
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

    systemd.services.sonarr.serviceConfig.UMask = lib.mkForce "0002";
  };
}
