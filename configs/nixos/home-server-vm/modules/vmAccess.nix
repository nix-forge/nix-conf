{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = {
    boot.loader.grub.memtest86.enable = lib.mkForce false;

    fileSystems."/srv/media-stack" = {
      device = "tmpfs";
      fsType = "tmpfs";
      options = [
        "uid=0"
        "gid=2000"
        "mode=0770"
        "size=4G"
      ];
    };

    networking.firewall.allowedTCPPorts = [
      22
      443
    ];

    services.journald.storage = "volatile";
    services.journald.extraConfig = ''
      RuntimeMaxUse=64M
      RuntimeKeepFree=32M
      SystemMaxUse=64M
    '';

    services.vaultwarden.enable = lib.mkForce true;
    services.bazarr.enable = lib.mkForce true;
    services.flaresolverr.enable = lib.mkForce true;
    services.lidarr.enable = lib.mkForce true;
    services.readarr.enable = lib.mkForce true;

    # VM profile convenience: keep key auth enabled, but allow password SSH
    # for local recovery/testing when host key material drifts.
    services.openssh.settings = {
      PasswordAuthentication = lib.mkForce true;
      KbdInteractiveAuthentication = lib.mkForce true;
    };

    systemd.services.vm-local-secrets = {
      description = "Populate local VM agenix secrets from mounted identity";
      wantedBy = [ "network-pre.target" ];
      after = [ "local-fs.target" ];
      before = [
        "network-pre.target"
        "acme-${"home.ianholloway.com"}.service"
      ];
      path = with pkgs; [ util-linux ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail

        for _ in $(seq 1 20); do
          if [ -e /dev/disk/by-label/vm-secrets ]; then
            break
          fi
          sleep 1
        done

        test -e /dev/disk/by-label/vm-secrets
        mkdir -p /run/vm-secrets /run/agenix
        if ! mountpoint -q /run/vm-secrets; then
          mount -t erofs -o ro /dev/disk/by-label/vm-secrets /run/vm-secrets
        fi

        test -r /run/vm-secrets/id_ed25519
        mkdir -p /run/agenix

        tmp_path="${config.age.secrets.cloudflare-acme-env.path}.tmp"
        ${config.age.ageBin} --decrypt \
          -i /run/vm-secrets/id_ed25519 \
          -o "$tmp_path" \
          '${config.age.secrets.cloudflare-acme-env.file}'
        chown ${config.age.secrets.cloudflare-acme-env.owner}:${config.age.secrets.cloudflare-acme-env.group} "$tmp_path"
        chmod ${config.age.secrets.cloudflare-acme-env.mode} "$tmp_path"
        mv -f "$tmp_path" '${config.age.secrets.cloudflare-acme-env.path}'

        tmp_path="${config.age.secrets.mullvad-wg-private-key.path}.tmp"
        ${config.age.ageBin} --decrypt \
          -i /run/vm-secrets/id_ed25519 \
          -o "$tmp_path" \
          '${config.age.secrets.mullvad-wg-private-key.file}'
        chown ${config.age.secrets.mullvad-wg-private-key.owner}:${config.age.secrets.mullvad-wg-private-key.group} "$tmp_path"
        chmod ${config.age.secrets.mullvad-wg-private-key.mode} "$tmp_path"
        mv -f "$tmp_path" '${config.age.secrets.mullvad-wg-private-key.path}'

        tmp_path="${config.age.secrets.vaultwarden-admin-token.path}.tmp"
        ${config.age.ageBin} --decrypt \
          -i /run/vm-secrets/id_ed25519 \
          -o "$tmp_path" \
          '${config.age.secrets.vaultwarden-admin-token.file}'
        chown ${config.age.secrets.vaultwarden-admin-token.owner}:${config.age.secrets.vaultwarden-admin-token.group} "$tmp_path"
        chmod ${config.age.secrets.vaultwarden-admin-token.mode} "$tmp_path"
        mv -f "$tmp_path" '${config.age.secrets.vaultwarden-admin-token.path}'
      '';
    };

    systemd.services.caddy = {
      after = [
        "vm-local-secrets.service"
        "acme-home.ianholloway.com.service"
      ];
      wants = [
        "vm-local-secrets.service"
        "acme-home.ianholloway.com.service"
      ];
    };

    systemd.services.vm-disable-nic-offload = {
      description = "Disable NIC offload features in VM test profile";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-pre.target" ];
      wants = [ "network-pre.target" ];
      path = with pkgs; [
        ethtool
        coreutils
      ];
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        set -eu
        for iface in /sys/class/net/*; do
          iface_name="$(basename "$iface")"
          if [ "$iface_name" = "lo" ]; then
            continue
          fi

          ethtool -K "$iface_name" tso off gso off gro off tx off rx off sg off || true
        done
      '';
    };

    security.tpm2.enable = lib.mkForce false;
    security.tpm2.abrmd.enable = lib.mkForce false;
    security.tpm2.pkcs11.enable = lib.mkForce false;
    security.tpm2.tctiEnvironment.enable = lib.mkForce false;
  };
}
