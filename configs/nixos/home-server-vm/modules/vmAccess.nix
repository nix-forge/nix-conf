{ lib, pkgs, ... }:
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

    age.identityPaths = lib.mkBefore [ "/vm-secrets/id_ed25519" ];

    system.activationScripts.vmMountSecrets = {
      deps = [ "specialfs" ];
      text = ''
        mkdir -p /vm-secrets
        if ! mountpoint -q /vm-secrets; then
          mount -t erofs -o ro /dev/disk/by-label/vm-secrets /vm-secrets
        fi

        if [ ! -s /vm-secrets/id_ed25519 ]; then
          echo "[vm-secrets] missing /vm-secrets/id_ed25519 for agenix decryption" >&2
          exit 1
        fi
      '';
    };

    system.activationScripts.agenixInstall.deps = lib.mkAfter [ "vmMountSecrets" ];

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

    # VM profile convenience: keep key auth enabled, but allow password SSH
    # for local recovery/testing when host key material drifts.
    services.openssh.settings = {
      PasswordAuthentication = lib.mkForce true;
      KbdInteractiveAuthentication = lib.mkForce true;
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
