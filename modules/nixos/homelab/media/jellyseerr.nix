{ config, ... }:
{
  services.jellyseerr = {
    enable = true;
    port = 5055;
    configDir = "${config.homelab.common.dataRoot}/jellyseerr";
    openFirewall = false;
  };
}
