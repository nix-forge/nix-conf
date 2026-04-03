{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = {
    services.qbittorrent = {
      package = lib.mkDefault pkgs.qbittorrent-nox;
      user = lib.mkDefault "qbittorrent";
      group = lib.mkDefault "qbittorrent";
      webuiPort = lib.mkDefault 8081;
      torrentingPort = lib.mkDefault 51413;
      openFirewall = lib.mkDefault false;
      serverConfig.Preferences.WebUI = {
        Address = lib.mkDefault "127.0.0.1";
        ReverseProxySupportEnabled = lib.mkDefault true;
      };
    };

    users.groups.${config.services.qbittorrent.group} = lib.mkIf config.services.qbittorrent.enable { };

    systemd.tmpfiles.rules = lib.mkIf config.services.qbittorrent.enable [
      "d ${config.services.qbittorrent.profileDir} 0750 ${config.services.qbittorrent.user} ${config.services.qbittorrent.group} - -"
    ];

    systemd.services.qbittorrent.serviceConfig.UMask = lib.mkIf config.services.qbittorrent.enable (
      lib.mkForce "0002"
    );
  };
}
