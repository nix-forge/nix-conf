{ lib, config, ... }:
{
  config = {
    users.groups.${config.services.sonarr.group} = { };

    systemd.tmpfiles.rules = [
      "d ${config.services.sonarr.dataDir} 0750 ${config.services.sonarr.user} ${config.services.sonarr.group} - -"
    ];

    services.sonarr = {
      enable = true;
      user = "sonarr";
      group = "sonarr";
      openFirewall = false;
      settings = {
        server = {
          port = 8989;
          bindaddress = "127.0.0.1";
          urlbase = "";
        };
      };
      environmentFiles = [ ];
    };

    systemd.services.sonarr.serviceConfig.UMask = lib.mkForce "0002";
  };
}
