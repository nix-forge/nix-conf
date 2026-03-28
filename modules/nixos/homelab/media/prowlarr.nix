{
  config,
  pkgs,
  lib,
  ...
}:
{
  services.prowlarr = {
    enable = true;
    package = pkgs.prowlarr;
    dataDir = "${config.homelab.common.dataRoot}/prowlarr";
    openFirewall = false;
    settings = {
      server = {
        port = 9696;
        bindaddress = "127.0.0.1";
        urlbase = "/prowlarr";
      };
    };
    environmentFiles = [ ];
  };

  systemd.services.prowlarr.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = lib.mkForce "prowlarr";
    Group = lib.mkForce "media";
  };
}
