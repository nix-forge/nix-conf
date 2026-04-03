{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = {
    services.prowlarr = {
      package = lib.mkDefault pkgs.prowlarr;
      openFirewall = lib.mkDefault false;
      settings.server = {
        port = lib.mkDefault 9696;
        bindaddress = lib.mkDefault "127.0.0.1";
        urlbase = lib.mkDefault "";
      };
    };

    users.groups.prowlarr = lib.mkIf config.services.prowlarr.enable { };

    systemd.tmpfiles.rules = lib.mkIf config.services.prowlarr.enable [
      "d ${config.services.prowlarr.dataDir} 0750 prowlarr prowlarr - -"
    ];

    systemd.services.prowlarr.serviceConfig = lib.mkIf config.services.prowlarr.enable {
      DynamicUser = lib.mkForce false;
      User = lib.mkForce "prowlarr";
      Group = lib.mkForce "prowlarr";
    };
  };
}
