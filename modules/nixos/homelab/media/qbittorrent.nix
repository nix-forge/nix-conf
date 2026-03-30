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

    primaryGroup = lib.mkOption {
      type = lib.types.str;
      default = "qbittorrent";
      description = "Primary group for qBittorrent service runtime.";
    };

    downloadsGroup = lib.mkOption {
      type = lib.types.str;
      default = "downloads";
      description = "Shared downloads group for media ingest workflow.";
    };
  };

  config = {
    assertions = [
      {
        assertion = (!cfg.bindToMullvad) || config.networking.wireguard.enable;
        message = "homelab.media.qbittorrent.bindToMullvad requires networking.wireguard.enable = true";
      }
    ];

    users.groups.${cfg.primaryGroup} = { };
    users.groups.${cfg.downloadsGroup} = { };

    users.users.qbittorrent.extraGroups = lib.mkAfter [ cfg.downloadsGroup ];

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 qbittorrent ${cfg.primaryGroup} - -"
      "d ${cfg.stackRoot} 0755 root root - -"
      "d ${cfg.stackRoot}/data 0755 root root - -"
      "d ${cfg.stackRoot}/data/torrents 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/data/torrents/incomplete 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/data/torrents/movies 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/data/torrents/tv 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/data/torrents/music 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/data/torrents/books 2770 root ${cfg.downloadsGroup} - -"
      "d ${cfg.stackRoot}/cache 0755 root root - -"
      "d ${cfg.stackRoot}/cache/qbittorrent 2770 root ${cfg.downloadsGroup} - -"
    ];

    services.qbittorrent = {
      enable = true;
      package = pkgs.qbittorrent-nox;
      profileDir = cfg.stateDir;
      user = "qbittorrent";
      group = cfg.primaryGroup;
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

    systemd.services.qbittorrent.serviceConfig.UMask = lib.mkForce "0002";
  };
}
