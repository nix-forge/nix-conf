{
  config,
  myLib,
  pkgs,
  ...
}:
let
  checkedShellText = myLib.writers.checkedShellText { inherit pkgs; };
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
    script = checkedShellText {
      name = "raspberry-pi-homebridge-backup";
      text =
        myLib.templates.renderText
          {
            name = "raspberry-pi-homebridge-backup-script.sh";
            text = ''
              # shellcheck shell=bash
              set -euo pipefail
              stamp="$(date -u +%Y%m%dT%H%M%SZ)"
              backup="''${STATE_DIRECTORY}/''${stamp}.tar.zst.age"
              partial="''${backup}.partial"
              trap 'rm -f "$partial"' EXIT

              ssh -T -S none -o BatchMode=yes -o IdentitiesOnly=yes \
                -o StrictHostKeyChecking=yes -i @userHome@/.ssh/id_ed25519 \
                ianmh@@network_raspberryPiServerAddress@ \
                'sudo -n tar --exclude=homebridge/backups --exclude=homebridge/homebridge.log -C /var/lib -cf - homebridge scrypted' |
                zstd -q -1 -c |
                age -R @raspberry_pi_keys_desktop_pub@ -o "$partial"

              mv "$partial" "$backup"
              trap - EXIT
            '';
          }
          {
            inherit userHome;
            network_raspberryPiServerAddress = network.raspberryPiServerAddress;
            raspberry_pi_keys_desktop_pub = ../../../raspberry-pi/local/keys/desktop.pub;
          };
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
