{ config, lib, ... }:
let
  fixtureSecrets = {
    ${config.my.media.secrets.cloudflareDdnsToken} = ''
      dummy-token
    '';
    ${config.my.media.secrets.vaultwardenEnv} = "";
    ${config.my.media.secrets.vpnGluetunEnv} = "";
    ${config.my.media.secrets.qbittorrentEnv} = ''
      TZ=Etc/UTC
      WEBUI_PORT=8080
      PUID=0
      PGID=0
      UMASK=002
      QBT_WEBUI_USERNAME=media-arr
      QBT_WEBUI_PASSWORD=media-arr-password
    '';
    ${config.my.media.secrets.piholeEnv} = ''
      TZ=Etc/UTC
    '';
    ${config.my.media.secrets.homebridgeEnv} = ''
      TZ=Etc/UTC
    '';
    ${config.my.media.secrets.scryptedEnv} = ''
      TZ=Etc/UTC
    '';
  };
  fixtureServiceNames = [
    "ddclient.service"
    "vaultwarden.service"
    "docker-gluetun.service"
    "docker-qbittorrent.service"
    "docker-homebridge.service"
    "docker-scrypted.service"
  ];
in
{
  systemd.services.agenix-install-secrets.enable = lib.mkForce false;

  systemd.services.media-vm-fixture-secrets = {
    description = "VM fixture secrets for media stack parity tests";
    wantedBy = [ "multi-user.target" ];
    before = fixtureServiceNames;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -eu
      install -d -m 0751 /run/agenix.d /run/agenix.d/fixture
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (name: value: ''
          cat > /run/agenix.d/fixture/${name} <<'EOF'
          ${value}
          EOF
          chmod 0400 /run/agenix.d/fixture/${name}
        '') fixtureSecrets
      )}
      ln -sfn /run/agenix.d/fixture /run/agenix
    '';
  };

  services.ddclient.enable = lib.mkForce false;

  virtualisation.oci-containers.containers.gluetun = lib.mkForce {
    image = "docker.io/library/alpine:3.20";
    autoStart = true;
    cmd = [
      "sh"
      "-c"
      "sleep infinity"
    ];
    volumes = [ "${config.my.media.storage.stateDir}/gluetun:/gluetun" ];
    ports = [ "127.0.0.1:${toString config.my.media.ports.qbittorrent}:8080/tcp" ];
    extraOptions = [
      "--restart=unless-stopped"
      "--security-opt=no-new-privileges:true"
    ];
  };
}
