{
  lib,
  pkgs,
  config,
  ...
}:
{
  config = {
    services.nzbget = {
      package = lib.mkDefault pkgs.nzbget;
      user = lib.mkDefault "nzbget";
      group = lib.mkDefault "nzbget";
      settings = {
        ControlIP = lib.mkDefault "127.0.0.1";
        ControlPort = lib.mkDefault 6789;
      };
    };

    users.groups.${config.services.nzbget.group} = lib.mkIf config.services.nzbget.enable { };

    systemd.tmpfiles.rules = lib.mkIf config.services.nzbget.enable [
      "d /var/lib/nzbget 0750 ${config.services.nzbget.user} ${config.services.nzbget.group} - -"
    ];

    systemd.services.nzbget.serviceConfig.UMask = lib.mkIf config.services.nzbget.enable (
      lib.mkForce "0002"
    );
  };
}
