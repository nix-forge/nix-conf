{ lib, config, ... }:
{
  config = {
    users.groups.${config.services.bazarr.group} = { };

    systemd.tmpfiles.rules = [
      "d ${config.services.bazarr.dataDir} 0750 ${config.services.bazarr.user} ${config.services.bazarr.group} - -"
    ];

    services.bazarr = {
      enable = true;
      user = "bazarr";
      group = "bazarr";
      listenPort = 6767;
      openFirewall = false;
    };

    systemd.services.bazarr.serviceConfig.UMask = lib.mkForce "0002";
  };
}
