{ lib, config, ... }:
{
  config = {
    users.groups.${config.services.radarr.group} = { };

    systemd.tmpfiles.rules = [
      "d ${config.services.radarr.dataDir} 0750 ${config.services.radarr.user} ${config.services.radarr.group} - -"
    ];

    services.radarr = {
      enable = true;
      user = "radarr";
      group = "radarr";
      openFirewall = false;
      settings = {
        server = {
          port = 7878;
          bindaddress = "127.0.0.1";
          urlbase = "";
        };
      };
      environmentFiles = [ ];
    };

    systemd.services.radarr.serviceConfig.UMask = lib.mkForce "0002";
  };
}
