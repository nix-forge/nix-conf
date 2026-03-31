{ lib, config, ... }:
{
  config = {
    users.groups.${config.services.readarr.group} = { };

    systemd.tmpfiles.rules = [
      "d ${config.services.readarr.dataDir} 0750 ${config.services.readarr.user} ${config.services.readarr.group} - -"
    ];

    services.readarr = {
      enable = true;
      user = "readarr";
      group = "readarr";
      openFirewall = false;
      settings = {
        server = {
          port = 8787;
          bindaddress = "127.0.0.1";
          urlbase = "";
        };
      };
      environmentFiles = [ ];
    };

    systemd.services.readarr.serviceConfig.UMask = lib.mkForce "0002";
  };
}
