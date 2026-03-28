{ config, ... }:
{
  services.sonarr = {
    enable = true;
    dataDir = "${config.homelab.common.dataRoot}/sonarr";
    user = "sonarr";
    group = "media";
    openFirewall = false;
    settings = {
      server = {
        port = 8989;
        bindaddress = "127.0.0.1";
        urlbase = "/sonarr";
      };
    };
    environmentFiles = [ ];
  };
}
