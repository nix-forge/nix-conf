{ lib, config, ... }:
{
  config = {
    services.readarr = {
      user = lib.mkDefault "readarr";
      group = lib.mkDefault "readarr";
      openFirewall = lib.mkDefault false;
      settings.server = {
        port = lib.mkDefault 8787;
        bindaddress = lib.mkDefault "127.0.0.1";
        urlbase = lib.mkDefault "";
      };
      environmentFiles = lib.mkDefault [ ];
    };

    users.groups.${config.services.readarr.group} = lib.mkIf config.services.readarr.enable { };

    systemd.tmpfiles.rules = lib.mkIf config.services.readarr.enable [
      "d ${config.services.readarr.dataDir} 0750 ${config.services.readarr.user} ${config.services.readarr.group} - -"
    ];

    systemd.services.readarr.serviceConfig.UMask = lib.mkIf config.services.readarr.enable (
      lib.mkForce "0002"
    );
  };
}
