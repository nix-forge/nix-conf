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
  options.homelab.media.qbittorrent = {
    bindToMullvad = lib.mkOption {
      type = lib.types.bool;
      default = config.networking.wireguard.enable;
      description = "Bind qBittorrent to wg-mullvad when WireGuard is enabled.";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/qbittorrent";
      description = "qBittorrent profile/state directory.";
    };

    stackRoot = lib.mkOption {
      type = lib.types.str;
      default = "/srv/media-stack";
      description = "Shared media stack root.";
    };

    sharedGroup = lib.mkOption {
      type = lib.types.str;
      default = "media";
      description = "Shared group for media stack access.";
    };

    sharedGroupGid = lib.mkOption {
      type = lib.types.int;
      default = 2000;
      description = "GID for the shared media group.";
    };
  };

  config = {
    assertions = [
      {
        assertion = (!cfg.bindToMullvad) || config.networking.wireguard.enable;
        message = "homelab.media.qbittorrent.bindToMullvad requires networking.wireguard.enable = true";
      }
    ];

    users.groups.${cfg.sharedGroup}.gid = lib.mkDefault cfg.sharedGroupGid;

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 qbittorrent ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot} 0755 root root - -"
      "d ${cfg.stackRoot}/data 2770 root ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot}/data/torrents 2770 root ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot}/data/torrents/incomplete 2770 root ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot}/data/torrents/movies 2770 root ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot}/data/torrents/tv 2770 root ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot}/data/torrents/music 2770 root ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot}/data/torrents/books 2770 root ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot}/cache 2770 root ${cfg.sharedGroup} - -"
      "d ${cfg.stackRoot}/cache/qbittorrent 2770 root ${cfg.sharedGroup} - -"
    ];

    services.qbittorrent = {
      enable = true;
      package = pkgs.qbittorrent-nox;
      profileDir = cfg.stateDir;
      user = "qbittorrent";
      group = cfg.sharedGroup;
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
