{ config, ... }:
{
  services.radarr = {
    enable = true;
    dataDir = "${config.homelab.common.dataRoot}/radarr";
    user = "radarr";
    group = "media";
    openFirewall = false;
    settings = {
      server = {
        port = 7878;
        bindaddress = "127.0.0.1";
        urlbase = "/radarr";
      };
    };
    environmentFiles = [ ];
  };
}
