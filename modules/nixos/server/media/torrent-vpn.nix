{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.media;
  state = cfg.storage.stateDir;
  qbtConfigDir = "${state}/qbittorrent/qBittorrent";
  qbtConfigFile = "${qbtConfigDir}/qBittorrent.conf";
  python = lib.getExe pkgs.python3;
in
{
  config = lib.mkIf (cfg.enable && cfg.services.torrent.enable) {
    users.groups.media = { };

    systemd.tmpfiles.rules = [
      "d ${state}/gluetun 0750 root media -"
      "d ${state}/qbittorrent 0750 root media -"
      "d ${qbtConfigDir} 0750 root media -"
      "d ${state}/nzbget 0750 nzbget media -"
    ];

    systemd.services.media-qbittorrent-config = {
      description = "Render qBittorrent secure WebUI configuration";
      wantedBy = [ "multi-user.target" ];
      before = [ "docker-qbittorrent.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
                set -eu
                env_file=${config.age.secrets.${cfg.secrets.qbittorrentEnv}.path}
                username=$(grep '^QBT_WEBUI_USERNAME=' "$env_file" | cut -d= -f2-)
                password=$(grep '^QBT_WEBUI_PASSWORD=' "$env_file" | cut -d= -f2-)
                if [ -z "$username" ] || [ -z "$password" ]; then
                  echo "QBT_WEBUI_USERNAME and QBT_WEBUI_PASSWORD must be set in ${cfg.secrets.qbittorrentEnv}" >&2
                  exit 1
                fi
                hash=$(QBT_PASSWORD="$password" ${python} - <<'PY'
        import base64
        import hashlib
        import os

        password = os.environ["QBT_PASSWORD"].encode()
        salt = os.urandom(16)
        derived = hashlib.pbkdf2_hmac("sha512", password, salt, 100000, 64)
        print(base64.b64encode(salt).decode() + ":" + base64.b64encode(derived).decode())
        PY
                )
                install -d -m 0750 ${qbtConfigDir}
                cat > ${qbtConfigFile} <<EOF
        [LegalNotice]
        Accepted=true

        [Preferences]
        Connection\\PortRangeMin=6881
        Downloads\\SavePath=${cfg.storage.torrentDir}/
        WebUI\\Address=127.0.0.1
        WebUI\\Username=$username
        WebUI\\Password_PBKDF2=@ByteArray($hash)
        WebUI\\CSRFProtection=true
        WebUI\\HostHeaderValidation=true
        WebUI\\SecureCookie=true
        EOF
                chmod 0640 ${qbtConfigFile}
      '';
    };

    virtualisation.oci-containers.containers = {
      gluetun = {
        image = "ghcr.io/qdm12/gluetun:v3.40.0";
        autoStart = true;
        environmentFiles = [ config.age.secrets.${cfg.secrets.vpnGluetunEnv}.path ];
        volumes = [ "${state}/gluetun:/gluetun" ];
        ports = [ "${toString cfg.ports.qbittorrent}:8080/tcp" ];
        extraOptions = [
          "--device=/dev/net/tun:/dev/net/tun"
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
        DestDir = cfg.storage.usenetDir;
        ControlIP = "127.0.0.1";
        ControlPort = cfg.ports.nzbget;
        UMask = "0002";
      };
    };

    users.users.nzbget.extraGroups = [ "media" ];
  };
}
