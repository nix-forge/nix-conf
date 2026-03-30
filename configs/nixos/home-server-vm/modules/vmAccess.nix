{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.vmAccess;
in
{
  options.homelab.vmAccess = {
    stackRoot = lib.mkOption {
      type = lib.types.str;
      default = "/srv/media-stack";
      description = "Shared media stack root mounted in VM profile.";
    };

    mediaGroupGid = lib.mkOption {
      type = lib.types.int;
      default = 2000;
      description = "GID applied to VM tmpfs mount for shared media access.";
    };

    stackRootSize = lib.mkOption {
      type = lib.types.str;
      default = "4G";
      description = "tmpfs size for the shared media stack root in VM profile.";
    };
  };

  config = {
    boot.loader.grub.memtest86.enable = lib.mkForce false;

    fileSystems.${cfg.stackRoot} = {
      device = "tmpfs";
      fsType = "tmpfs";
      options = [
        "uid=0"
        "gid=${toString cfg.mediaGroupGid}"
        "mode=0770"
        "size=${cfg.stackRootSize}"
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

    homelab.media.qbittorrent.bindToMullvad = lib.mkForce true;

    services.vaultwarden.enable = lib.mkForce true;
    services.bazarr.enable = lib.mkForce true;
    services.flaresolverr.enable = lib.mkForce true;
    services.lidarr.enable = lib.mkForce true;
    services.readarr.enable = lib.mkForce true;

    systemd.services.vm-local-secrets = {
      description = "Populate local VM agenix secrets from mounted identity";
      wantedBy = [ "network-pre.target" ];
      after = [ "local-fs.target" ];
      before = [
        "network-pre.target"
        "tailscaled-autoconnect.service"
        "tailscale-cert.service"
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

        tmp_path="${config.age.secrets.tailscale-auth-key.path}.tmp"
        ${config.age.ageBin} --decrypt \
          -i /run/vm-secrets/id_ed25519 \
          -o "$tmp_path" \
          '${config.age.secrets.tailscale-auth-key.file}'
        if ! grep -q '^tskey-' "$tmp_path"; then
          echo 'tailscale-auth-key does not look like a Tailscale auth key; expected a value starting with tskey-' >&2
          rm -f "$tmp_path"
          exit 1
        fi
        chown ${config.age.secrets.tailscale-auth-key.owner}:${config.age.secrets.tailscale-auth-key.group} "$tmp_path"
        chmod ${config.age.secrets.tailscale-auth-key.mode} "$tmp_path"
        mv -f "$tmp_path" '${config.age.secrets.tailscale-auth-key.path}'

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

    systemd.services.tailscaled-autoconnect = {
      after = [ "vm-local-secrets.service" ];
      requires = [ "vm-local-secrets.service" ];
    };

    systemd.services.tailscale-cert = {
      after = [ "vm-local-secrets.service" ];
      requires = [ "vm-local-secrets.service" ];
    };

    systemd.services.tailscale-nginx-auth = {
      after = [
        "vm-local-secrets.service"
        "tailscaled-autoconnect.service"
      ];
      wants = [
        "vm-local-secrets.service"
        "tailscaled-autoconnect.service"
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
