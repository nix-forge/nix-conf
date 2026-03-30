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

    primaryGroup = lib.mkOption {
      type = lib.types.str;
      default = "nzbget";
      description = "Primary group for NZBGet service runtime.";
    };

    downloadsGroup = lib.mkOption {
      type = lib.types.str;
      default = "downloads";
      description = "Shared downloads group for media ingest workflow.";
    };
  };

  config = {
    users.groups.${cfg.primaryGroup} = { };
    users.groups.${cfg.downloadsGroup} = { };

    users.users.nzbget.extraGroups = lib.mkAfter [ cfg.downloadsGroup ];

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 nzbget ${cfg.primaryGroup} - -"
      "d ${cfg.stackRoot} 0755 root root - -"
      "d ${cfg.stackRoot}/data 0755 root root - -"
      "d ${cfg.stackRoot}/data/usenet 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/data/usenet/incomplete 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/data/usenet/movies 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/data/usenet/tv 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/data/usenet/music 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/data/usenet/books 2770 root ${cfg.downloadsGroup} - -"
    ];

    services.nzbget = {
      enable = true;
      package = pkgs.nzbget;
      user = "nzbget";
      group = cfg.primaryGroup;
      settings = {
        ControlIP = "127.0.0.1";
        ControlPort = 6789;
      };
    };

    systemd.services.nzbget.serviceConfig.UMask = lib.mkForce "0002";

  };
}
