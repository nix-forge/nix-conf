{ config, lib, ... }:
let
  cfg = config.my.media;
  configDir = "/var/lib/jellyseerr/config";
in
{
  config = lib.mkIf (cfg.enable && cfg.services.jellyseerr.enable) {
    users.groups.jellyseerr = { };
    users.users.jellyseerr = {
      isSystemUser = true;
      group = "jellyseerr";
      extraGroups = [ "media" ];
      home = configDir;
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/jellyseerr 0750 jellyseerr media -"
      "d ${configDir} 0750 jellyseerr media -"
    ];

    services.jellyseerr = {
      enable = true;
      openFirewall = false;
      inherit configDir;
      port = cfg.ports.jellyseerr;
    };
  };
}
