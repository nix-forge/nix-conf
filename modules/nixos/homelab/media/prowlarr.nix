{
  config,
  pkgs,
  lib,
  ...
}:
{
  users.groups.prowlarr = { };

  systemd.tmpfiles.rules = [ "d ${config.services.prowlarr.dataDir} 0750 prowlarr prowlarr - -" ];

  services.prowlarr = {
    enable = true;
    package = pkgs.prowlarr;
    openFirewall = false;
    settings = {
      server = {
        port = 9696;
        bindaddress = "127.0.0.1";
        urlbase = "";
      };
    };
  };

  systemd.services.prowlarr.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = lib.mkForce "prowlarr";
    Group = lib.mkForce "prowlarr";
  };
}
