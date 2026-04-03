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
      "d ${cfg.storage.moviesDir} 0770 root media -"
      "d ${cfg.storage.showsDir} 0770 root media -"
      "d ${cfg.storage.torrentDir} 0770 root media -"
      "d ${cfg.storage.usenetDir} 0770 root media -"
    ];

    services.radarr = {
      enable = true;
      openFirewall = false;
      dataDir = "${state}/radarr";
      settings = {
        log.analyticsEnabled = false;
        server = {
          port = cfg.ports.radarr;
          bindAddress = "127.0.0.1";
        };
        update = {
          automatically = false;
          mechanism = "external";
        };
      };
    };

    services.sonarr = {
      enable = true;
      openFirewall = false;
      dataDir = "${state}/sonarr";
      settings = {
        log.analyticsEnabled = false;
        server = {
          port = cfg.ports.sonarr;
          bindAddress = "127.0.0.1";
        };
        update = {
          automatically = false;
          mechanism = "external";
        };
      };
    };

    services.prowlarr = {
      enable = true;
      openFirewall = false;
      dataDir = "${state}/prowlarr";
      settings = {
        log.analyticsEnabled = false;
        server = {
          port = cfg.ports.prowlarr;
          bindAddress = "127.0.0.1";
        };
        update = {
          automatically = false;
          mechanism = "external";
        };
      };
    };

    services.bazarr = {
      enable = true;
      openFirewall = false;
      dataDir = "${state}/bazarr";
    };
  };
}
