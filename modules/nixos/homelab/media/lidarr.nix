{ config, ... }:
{
  services.lidarr = {
    enable = true;
    dataDir = "${config.homelab.common.dataRoot}/lidarr";
    user = "lidarr";
    group = "media";
    openFirewall = false;
    settings = {
      server = {
        port = 8686;
        bindaddress = "127.0.0.1";
        urlbase = "/lidarr";
      };
    };
    environmentFiles = [ ];
  };
}
