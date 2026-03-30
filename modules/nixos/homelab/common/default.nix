{ lib, config, ... }:
let
  cfg = config.homelab.common;
in
{
  options.homelab.common = {
    dataRoot = lib.mkOption {
      type = lib.types.str;
      default = "/srv/homelab";
      description = "Base directory for homelab application data.";
    };

    mediaRoot = lib.mkOption {
      type = lib.types.str;
      default = "/srv/media";
      description = "Base directory for media libraries.";
    };

    downloadsRoot = lib.mkOption {
      type = lib.types.str;
      default = "/srv/downloads";
      description = "Base directory for completed/incomplete downloads.";
    };

  };

  config = {
    systemd.tmpfiles.rules = [
      "d ${cfg.dataRoot} 0750 root media - -"
      "d ${cfg.dataRoot}/jellyfin 0750 jellyfin media - -"
      "d ${cfg.dataRoot}/sonarr 0750 sonarr media - -"
      "d ${cfg.dataRoot}/radarr 0750 radarr media - -"
      "d ${cfg.dataRoot}/lidarr 0750 lidarr media - -"
      "d ${cfg.dataRoot}/readarr 0750 readarr media - -"
      "d ${cfg.dataRoot}/bazarr 0750 bazarr media - -"
      "d ${cfg.dataRoot}/prowlarr 0750 prowlarr media - -"
      "d ${cfg.dataRoot}/qbittorrent 0750 qbittorrent media - -"
      "d ${cfg.mediaRoot} 0750 root media - -"
      "d ${cfg.downloadsRoot} 0770 root media - -"
      "d ${cfg.downloadsRoot}/incomplete 0770 root media - -"
      "d ${cfg.downloadsRoot}/complete 0770 root media - -"
    ];

    users.groups.media.gid = lib.mkDefault 2000;
  };
}
