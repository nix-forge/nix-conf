{ config, ... }:
{
  services.jellyfin = {
    enable = true;
    user = "jellyfin";
    group = "media";
    dataDir = "${config.homelab.common.dataRoot}/jellyfin";
    openFirewall = false;
  };

  users.users.jellyfin.extraGroups = [ "media" ];
}
