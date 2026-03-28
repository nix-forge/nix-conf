{ config, pkgs, ... }:
{
  services.qbittorrent = {
    enable = true;
    package = pkgs.qbittorrent-nox;
    profileDir = "${config.homelab.common.dataRoot}/qbittorrent";
    user = "qbittorrent";
    group = "media";
    webuiPort = 8081;
    torrentingPort = 51413;
    openFirewall = false;
    serverConfig = {
      Preferences.Connection = {
        Interface = "wg-mullvad";
        InterfaceAddress = "10.71.216.231";
      };
      Preferences.WebUI = {
        Address = "127.0.0.1";
        ReverseProxySupportEnabled = true;
      };
    };
  };
}
