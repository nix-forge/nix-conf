{
  profile ? "home-server",
}:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  values = import ./integration-values.nix { inherit profile; };
in
{
  assertions = [
    {
      assertion = lib.hasAttrByPath [ "age" "secrets" "homelab-reconcile-env" ] config;
      message = "age.secrets.homelab-reconcile-env must exist for homelab integration reconcile.";
    }
  ];

  systemd.services.homelab-reconcile = {
    description = "Reconcile homelab service integrations";
    after = [
      "network-online.target"
      "prowlarr.service"
      "sonarr.service"
      "radarr.service"
      "lidarr.service"
      "readarr.service"
      "qbittorrent.service"
      "nzbget.service"
      "seerr.service"
      "jellyfin.service"
    ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Group = "root";
      EnvironmentFile = config.age.secrets.homelab-reconcile-env.path;
      StateDirectory = "homelab-reconcile";
      RuntimeDirectory = "homelab-reconcile";
      RuntimeDirectoryMode = "0700";
      ExecStart = lib.getExe (
        pkgs.writeShellApplication {
          name = "homelab-reconcile";
          runtimeInputs = with pkgs; [
            curl
            jq
            python3
          ];
          text = ''
            set -euo pipefail
            umask 077

            export HOME=/run/homelab-reconcile
            mkdir -p "$HOME"

            export HOMELAB_INTEGRATION_VALUES='${builtins.toJSON values}'
            export PYTHONPATH='${../../../../scripts/homelab}'
            exec ${pkgs.python3}/bin/python3 ${../../../../scripts/homelab/reconcile-stack.py}
          '';
        }
      );
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [
        "/var/lib/homelab-reconcile"
        "/run/homelab-reconcile"
      ];
      TimeoutStartSec = "15min";
    };
  };

  systemd.timers.homelab-reconcile = {
    description = "Periodic homelab integration reconciliation";
    wantedBy = [ "timers.target" ];
    partOf = [ "homelab-reconcile.service" ];
    timerConfig = {
      OnBootSec = values.timer.onBootSec;
      OnUnitActiveSec = values.timer.onUnitActiveSec;
      RandomizedDelaySec = values.timer.randomizedDelaySec;
      Persistent = true;
      Unit = "homelab-reconcile.service";
    };
  };
}
