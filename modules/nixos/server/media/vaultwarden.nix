{ config, lib, ... }:
let
  cfg = config.my.media;
  state = cfg.storage.stateDir;
in
{
  config = lib.mkIf (cfg.enable && cfg.services.vaultwarden.enable) {
    systemd.tmpfiles.rules = [
      "d ${state}/vaultwarden 0750 vaultwarden media -"
      "d ${state}/vaultwarden/backup 0750 vaultwarden media -"
    ];

    services.vaultwarden = {
      enable = true;
      backupDir = "${state}/vaultwarden/backup";
      environmentFile = config.age.secrets.${cfg.secrets.vaultwardenEnv}.path;
      config = {
        DOMAIN = "https://${cfg.hosts.vaultwardenPublic}";
        ROCKET_ADDRESS = "127.0.0.1";
        ROCKET_PORT = cfg.ports.vaultwarden;
        SIGNUPS_ALLOWED = false;
        INVITATIONS_ALLOWED = false;
        WEBSOCKET_ENABLED = true;
      };
    };
  };
}
