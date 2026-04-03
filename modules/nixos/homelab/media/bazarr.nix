{ lib, config, ... }:
{
  config = {
    services.bazarr = {
      user = lib.mkDefault "bazarr";
      group = lib.mkDefault "bazarr";
      listenPort = lib.mkDefault 6767;
      openFirewall = lib.mkDefault false;
    };

    users.groups.${config.services.bazarr.group} = lib.mkIf config.services.bazarr.enable { };

    systemd.tmpfiles.rules = lib.mkIf config.services.bazarr.enable [
      "d ${config.services.bazarr.dataDir} 0750 ${config.services.bazarr.user} ${config.services.bazarr.group} - -"
    ];

    systemd.services.bazarr.serviceConfig.UMask = lib.mkIf config.services.bazarr.enable (
      lib.mkForce "0002"
    );
  };
}
