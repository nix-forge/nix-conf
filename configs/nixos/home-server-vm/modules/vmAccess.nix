{
  config,
  lib,
  pkgs,
  ...
}:
{
  homelab.proxy.vmHttpAccess.enable = true;
  homelab.proxy.tailscaleTls.enable = lib.mkForce false;

  boot.loader.grub.memtest86.enable = lib.mkForce false;

  fileSystems.${config.homelab.common.dataRoot} = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [
      "uid=0"
      "gid=2000"
      "mode=0770"
      "size=2G"
    ];
  };

  fileSystems.${config.homelab.common.downloadsRoot} = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [
      "uid=0"
      "gid=2000"
      "mode=0770"
      "size=1G"
    ];
  };

  fileSystems.${config.homelab.common.mediaRoot} = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [
      "uid=0"
      "gid=2000"
      "mode=0770"
      "size=512M"
    ];
  };

  networking.firewall.allowedTCPPorts = [
    22
    8080
  ];

  services.openssh.settings = {
    PasswordAuthentication = lib.mkForce true;
    KbdInteractiveAuthentication = lib.mkForce true;
  };

  services.journald.storage = "volatile";
  services.journald.extraConfig = ''
    RuntimeMaxUse=64M
    RuntimeKeepFree=32M
    SystemMaxUse=64M
  '';

  services.fail2ban.enable = lib.mkForce false;

  services.jellyseerr.configDir = lib.mkForce "/var/lib/jellyseerr/config";
  services.sonarr.dataDir = lib.mkForce "/var/lib/sonarr/.config/NzbDrone";

  homelab.media.qbittorrent.bindToMullvad = lib.mkForce false;

  networking.wireguard.enable = lib.mkForce false;
  networking.wireguard.interfaces = lib.mkForce { };

  services.tailscale.enable = lib.mkForce false;
  systemd.services.tailscale-cert.enable = lib.mkForce false;
  systemd.timers.tailscale-cert.enable = lib.mkForce false;

  systemd.network.networks."40-wg-mullvad" = lib.mkForce { };
  networking.nftables.tables.homelab-vpn = lib.mkForce {
    family = "inet";
    content = "";
  };

  services.frigate.enable = lib.mkForce false;
  services.vaultwarden.enable = lib.mkForce true;
  services.bazarr.enable = lib.mkForce true;
  services.flaresolverr.enable = lib.mkForce false;
  services.lidarr.enable = lib.mkForce true;
  services.readarr.enable = lib.mkForce true;

  users.users.prowlarr = {
    isSystemUser = lib.mkForce true;
    uid = lib.mkForce 2003;
    group = lib.mkForce "media";
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

}
