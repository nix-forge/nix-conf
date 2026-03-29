{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.media.qbittorrent;
in
{
  options.homelab.media.qbittorrent.bindToMullvad = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Bind qBittorrent to wg-mullvad when WireGuard is enabled.";
  };

  config = {
    assertions = [
      {
        assertion = (!cfg.bindToMullvad) || config.networking.wireguard.enable;
        message = "homelab.media.qbittorrent.bindToMullvad requires networking.wireguard.enable = true";
      }
    ];

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
        Preferences =
          (lib.optionalAttrs cfg.bindToMullvad {
            Connection = {
              Interface = "wg-mullvad";
              InterfaceAddress = "10.71.216.231";
            };
          })
          // {
            WebUI = {
              Address = "127.0.0.1";
              ReverseProxySupportEnabled = true;
            };
          };
      };
    };
  };
}
