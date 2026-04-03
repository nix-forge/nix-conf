{ lib, config, ... }:
{
  config = {
    services.jellyfin = {
      user = lib.mkDefault "jellyfin";
      group = lib.mkDefault "jellyfin";
      openFirewall = lib.mkDefault false;
    };

    users.groups.${config.services.jellyfin.group} = lib.mkIf config.services.jellyfin.enable { };

    systemd.tmpfiles.rules = lib.mkIf config.services.jellyfin.enable [
      "d ${config.services.jellyfin.dataDir} 0750 ${config.services.jellyfin.user} ${config.services.jellyfin.group} - -"
    ];
  };
}
