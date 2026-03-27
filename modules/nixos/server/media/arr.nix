{ config, lib, ... }:
let
  cfg = config.my.media;
  state = cfg.storage.stateDir;
in
{
  config = lib.mkIf (cfg.enable && cfg.services.arr.enable) {
    users.groups = {
      media = { };
      prowlarr = { };
    };

    users.users.prowlarr = {
      isSystemUser = true;
      group = "prowlarr";
      extraGroups = [ "media" ];
    };

    users.users.radarr.extraGroups = [ "media" ];
    users.users.sonarr.extraGroups = [ "media" ];
    users.users.bazarr.extraGroups = [ "media" ];

    systemd.tmpfiles.rules = [
      "d ${state}/radarr 0750 radarr media -"
      "d ${state}/sonarr 0750 sonarr media -"
      "d ${state}/prowlarr 0750 prowlarr media -"
      "d ${state}/bazarr 0750 bazarr media -"
      "d ${cfg.storage.mediaDir} 0770 root media -"
      "d ${cfg.storage.downloadsDir} 0770 root media -"
    ];

    services.radarr = {
      enable = true;
      openFirewall = false;
      dataDir = "${state}/radarr";
    };

    services.sonarr = {
      enable = true;
      openFirewall = false;
      dataDir = "${state}/sonarr";
    };

    services.prowlarr = {
      enable = true;
      openFirewall = false;
      dataDir = "${state}/prowlarr";
    };

    services.bazarr = {
      enable = true;
      openFirewall = false;
      dataDir = "${state}/bazarr";
    };
  };
}
