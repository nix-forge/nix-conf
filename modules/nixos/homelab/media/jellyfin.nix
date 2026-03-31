{ config, ... }:
{
  config = {
    users.groups.${config.services.jellyfin.group} = { };

    systemd.tmpfiles.rules = [
      "d ${config.services.jellyfin.dataDir} 0750 ${config.services.jellyfin.user} ${config.services.jellyfin.group} - -"
    ];

    services.jellyfin = {
      enable = true;
      user = "jellyfin";
      group = "jellyfin";
      openFirewall = false;
    };
  };
}
