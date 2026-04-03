{ lib, config, ... }:
{
  config = {
    services.lidarr = {
      user = lib.mkDefault "lidarr";
      group = lib.mkDefault "lidarr";
      openFirewall = lib.mkDefault false;
      settings.server = {
        port = lib.mkDefault 8686;
        bindaddress = lib.mkDefault "127.0.0.1";
        urlbase = lib.mkDefault "";
      };
      environmentFiles = lib.mkDefault [ ];
    };

    users.groups.${config.services.lidarr.group} = lib.mkIf config.services.lidarr.enable { };

    systemd.tmpfiles.rules = lib.mkIf config.services.lidarr.enable [
      "d ${config.services.lidarr.dataDir} 0750 ${config.services.lidarr.user} ${config.services.lidarr.group} - -"
    ];

    systemd.services.lidarr.serviceConfig.UMask = lib.mkIf config.services.lidarr.enable (
      lib.mkForce "0002"
    );
  };
}
