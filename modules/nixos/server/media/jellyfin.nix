{ config, lib, ... }:
let
  cfg = config.my.media;
  state = cfg.storage.stateDir;
in
{
  config = lib.mkIf (cfg.enable && cfg.services.jellyfin.enable) {
    users.users.jellyfin.extraGroups = [ "media" ];

    systemd.tmpfiles.rules = [ "d ${state}/jellyfin 0750 jellyfin media -" ];

    services.jellyfin = {
      enable = true;
      openFirewall = false;
      dataDir = "${state}/jellyfin";
    };
  };
}
