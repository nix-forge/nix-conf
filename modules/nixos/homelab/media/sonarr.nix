{ lib, config, ... }:
{
  config = {
    services.sonarr = {
      user = lib.mkDefault "sonarr";
      group = lib.mkDefault "sonarr";
      openFirewall = lib.mkDefault false;
      settings.server = {
        port = lib.mkDefault 8989;
        bindaddress = lib.mkDefault "127.0.0.1";
        urlbase = lib.mkDefault "";
      };
      environmentFiles = lib.mkDefault [ ];
    };

    users.groups.${config.services.sonarr.group} = lib.mkIf config.services.sonarr.enable { };

    systemd.tmpfiles.rules = lib.mkIf config.services.sonarr.enable [
      "d ${config.services.sonarr.dataDir} 0750 ${config.services.sonarr.user} ${config.services.sonarr.group} - -"
    ];

    systemd.services.sonarr.serviceConfig.UMask = lib.mkIf config.services.sonarr.enable (
      lib.mkForce "0002"
    );
  };
}
