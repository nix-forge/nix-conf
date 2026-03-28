{ config, ... }:
{
  services.readarr = {
    enable = true;
    dataDir = "${config.homelab.common.dataRoot}/readarr";
    user = "readarr";
    group = "media";
    openFirewall = false;
    settings = {
      server = {
        port = 8787;
        bindaddress = "127.0.0.1";
        urlbase = "/readarr";
      };
    };
    environmentFiles = [ ];
  };
}
