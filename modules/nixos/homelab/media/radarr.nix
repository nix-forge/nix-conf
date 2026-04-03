{ lib, config, ... }:
{
  config = {
    services.radarr = {
      user = lib.mkDefault "radarr";
      group = lib.mkDefault "radarr";
      openFirewall = lib.mkDefault false;
      settings.server = {
        port = lib.mkDefault 7878;
        bindaddress = lib.mkDefault "127.0.0.1";
        urlbase = lib.mkDefault "";
      };
      environmentFiles = lib.mkDefault [ ];
    };

    users.groups.${config.services.radarr.group} = lib.mkIf config.services.radarr.enable { };

    systemd.tmpfiles.rules = lib.mkIf config.services.radarr.enable [
      "d ${config.services.radarr.dataDir} 0750 ${config.services.radarr.user} ${config.services.radarr.group} - -"
    ];

    systemd.services.radarr.serviceConfig.UMask = lib.mkIf config.services.radarr.enable (
      lib.mkForce "0002"
    );
  };
}
