{ lib, config, ... }:
{
  config = {
    users.groups.${config.services.lidarr.group} = { };

    systemd.tmpfiles.rules = [
      "d ${config.services.lidarr.dataDir} 0750 ${config.services.lidarr.user} ${config.services.lidarr.group} - -"
    ];

    services.lidarr = {
      enable = true;
      user = "lidarr";
      group = "lidarr";
      openFirewall = false;
      settings = {
        server = {
          port = 8686;
          bindaddress = "127.0.0.1";
          urlbase = "";
        };
      };
      environmentFiles = [ ];
    };

    systemd.services.lidarr.serviceConfig.UMask = lib.mkForce "0002";
  };
}
