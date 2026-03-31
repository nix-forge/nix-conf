{
  lib,
  pkgs,
  config,
  ...
}:
{
  config = {
    users.groups.${config.services.nzbget.group} = { };

    systemd.tmpfiles.rules = [
      "d /var/lib/nzbget 0750 ${config.services.nzbget.user} ${config.services.nzbget.group} - -"
    ];

    services.nzbget = {
      enable = true;
      package = pkgs.nzbget;
      user = "nzbget";
      group = "nzbget";
      # TODO: Configure the correct settings using documentation from https://github.com/nzbgetcom/nzbget/blob/develop/nzbget.conf
      settings = {
        ControlIP = "127.0.0.1";
        ControlPort = 6789;
      };
    };

    systemd.services.nzbget.serviceConfig.UMask = lib.mkForce "0002";

  };
}
