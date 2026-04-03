{ config, lib, ... }:
let
  cfg = config.my.media;
  state = cfg.storage.stateDir;
in
{
  config = lib.mkIf (cfg.enable && cfg.services.jellyfin.enable) {
    users.users.jellyfin.extraGroups = [ "media" ];

    systemd.tmpfiles.rules = [
      "d ${state}/jellyfin 0750 jellyfin media -"
      "d ${state}/jellyfin/cache 0750 jellyfin media -"
      "d ${state}/jellyfin/log 0750 jellyfin media -"
      "d ${state}/jellyfin/transcodes 0750 jellyfin media -"
    ];

    services.jellyfin = {
      enable = true;
      openFirewall = false;
      dataDir = "${state}/jellyfin";
      cacheDir = "${state}/jellyfin/cache";
      logDir = "${state}/jellyfin/log";
      transcoding = {
        deleteSegments = true;
        throttleTranscoding = true;
        enableSubtitleExtraction = false;
      };
    };
  };
}
