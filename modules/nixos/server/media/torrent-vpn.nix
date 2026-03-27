{ config, lib, ... }:
let
  cfg = config.my.media;
  state = cfg.storage.stateDir;
in
{
  config = lib.mkIf (cfg.enable && cfg.services.torrent.enable) {
    users.groups.media = { };

    systemd.tmpfiles.rules = [
      "d ${state}/gluetun 0750 root media -"
      "d ${state}/qbittorrent 0750 root media -"
      "d ${state}/nzbget 0750 nzbget media -"
    ];

    virtualisation.oci-containers.containers = {
      gluetun = {
        image = "ghcr.io/qdm12/gluetun:v3.40.0";
        autoStart = true;
        environmentFiles = [ config.age.secrets.${cfg.secrets.vpnGluetunEnv}.path ];
        volumes = [ "${state}/gluetun:/gluetun" ];
        ports = [ "127.0.0.1:${toString cfg.ports.qbittorrent}:8080/tcp" ];
        extraOptions = [
          "--cap-add=NET_ADMIN"
          "--cap-add=NET_RAW"
          "--health-cmd=gluetun healthcheck"
          "--health-interval=30s"
          "--health-timeout=10s"
          "--health-retries=6"
          "--restart=unless-stopped"
          "--security-opt=no-new-privileges:true"
        ];
      };

      qbittorrent = {
        image = "linuxserver/qbittorrent:5.0.4";
        autoStart = true;
        dependsOn = [ "gluetun" ];
        environmentFiles = [ config.age.secrets.${cfg.secrets.qbittorrentEnv}.path ];
        volumes = [
          "${state}/qbittorrent:/config"
          "${cfg.storage.downloadsDir}:/downloads"
        ];
        extraOptions = [
          "--network=container:gluetun"
          "--restart=unless-stopped"
          "--security-opt=no-new-privileges:true"
        ];
      };
    };

    services.nzbget = {
      enable = true;
      settings = {
        MainDir = cfg.storage.downloadsDir;
        DestDir = "${cfg.storage.downloadsDir}/usenet";
        ControlIP = "127.0.0.1";
        ControlPort = cfg.ports.nzbget;
        UMask = "0002";
      };
    };

    users.users.nzbget.extraGroups = [ "media" ];
  };
}
