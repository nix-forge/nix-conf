{ config, ... }:
{
  services.bazarr = {
    enable = true;
    dataDir = "${config.homelab.common.dataRoot}/bazarr";
    user = "bazarr";
    group = "media";
    listenPort = 6767;
    openFirewall = false;
  };
}
