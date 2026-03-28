{ config, ... }:
{
  services.homebridge = {
    enable = true;
    openFirewall = false;
    userStoragePath = "${config.homelab.common.dataRoot}/homebridge";
    pluginPath = "${config.homelab.common.dataRoot}/homebridge/node_modules";
    settings = { };
    uiSettings = {
      port = 8581;
    };
    environmentFile = null;
  };
}
