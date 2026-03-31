{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = {
    users.groups.${config.services.qbittorrent.group} = { };

    systemd.tmpfiles.rules = [
      "d ${config.services.qbittorrent.profileDir} 0750 ${config.services.qbittorrent.user} ${config.services.qbittorrent.group} - -"
    ];

    services.qbittorrent = {
      enable = true;
      package = pkgs.qbittorrent-nox;
      user = "qbittorrent";
      group = "qbittorrent";
      webuiPort = 8081;
      torrentingPort = 51413;
      openFirewall = false;
      serverConfig = {
        Preferences = {
          WebUI = {
            Address = "127.0.0.1";
            ReverseProxySupportEnabled = true;
          };
        };
      };
    };

    systemd.services.qbittorrent.serviceConfig.UMask = lib.mkForce "0002";
  };
}
