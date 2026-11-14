{ config, pkgs, ... }:
let
  network = builtins.fromJSON (builtins.readFile ../../../../shared/local/network.json);
  userHome = config.users.users.ianmh.home;
in
{
  # Pull mutable Homebridge and Scrypted state once a week. The Pi only
  # streams tar; compression and encryption happen off-device. Keep the
  # historical unit and state directory names so existing archives remain.
  systemd.services.raspberry-pi-homebridge-backup = {
    description = "Encrypted off-device Raspberry Pi application backup";
    after = [ "homelab-lan-ready.service" ];
    requires = [ "homelab-lan-ready.service" ];
    path = with pkgs; [
      age
      coreutils
      findutils
      openssh
      zstd
    ];
    serviceConfig = {
      Type = "oneshot";
      User = "ianmh";
      StateDirectory = "raspberry-pi-homebridge-backups";
      StateDirectoryMode = "0700";
      UMask = "0077";
      TimeoutStartSec = "30min";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      PrivateTmp = true;
    };
    script =
      (import ../../../../../lib/templates/text.nix) ./scripts/raspberry-pi-homebridge-backup-script.sh
        {
          inherit userHome;
          network_raspberryPiServerAddress = network.raspberryPiServerAddress;
          raspberry_pi_keys_desktop_pub = ../../../raspberry-pi/local/keys/desktop.pub;
        };
  };

  systemd.timers.raspberry-pi-homebridge-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun *-*-* 03:30:00";
      Persistent = true;
      RandomizedDelaySec = "30m";
    };
  };
}
