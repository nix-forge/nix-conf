{
  config,
  inputs,
  lib,
  ...
}:
let
  qbitBootstrapReady = lib.all (name: builtins.pathExists (../secrets + "/homelab-${name}.age")) [
    "vpn-private-key"
    "qbittorrent-username"
    "qbittorrent-password-hash"
  ];
in
{
  imports = [ inputs.nix-homelab.nixosModules.default ];

  assertions = lib.optional (qbitBootstrapReady && config.hardware.storage.homelabHdd.enable) {
    assertion =
      config.homelab.vpn.enable
      && config.homelab.apps.qbittorrent.vpn.enable
      && config.systemd.services.qbittorrent.vpn.enable;
    message = "Desktop qBittorrent must remain in the VPN namespace even during staged homelab bootstrap.";
  };

  # The provider profile stays public host configuration, but the WireGuard
  # private key is delivered only at service activation time. Declaring it now
  # makes nix-seal expose the create-only bootstrap workflow without placing a
  # credential in this expression or the Nix store.
  nixSeal.secrets.homelab-vpn-private-key.phase = "services";

  homelab = {
    # Apply the desktop scheduling policy now. Start qBittorrent once its login
    # and VPN key exist so its own Web UI can generate the first API key.
    profiles.desktop.enable = config.hardware.storage.homelabHdd.enable;
    vpn.enable = lib.mkIf (qbitBootstrapReady && config.hardware.storage.homelabHdd.enable) true;
    apps.qbittorrent = lib.mkIf (qbitBootstrapReady && config.hardware.storage.homelabHdd.enable) {
      enable = true;
      credentialsFile = config.nixSeal.templates.homelab-qbittorrent-webui-ini.path;
    };

    # Mullvad's assigned addresses and relay material are public provider
    # configuration. Pinning a literal, currently active endpoint avoids host
    # DNS before the tunnel exists. Use the verified Seattle relay; the previous
    # relay stopped answering handshakes. Recheck connectivity when changing it.
    vpn = {
      interface = {
        privateKeyFile = config.nixSeal.secrets.homelab-vpn-private-key.path;
        addressIPv4 = "10.69.242.111";
        addressIPv6 = "fc00:bbbb:bbbb:bb01::6:f26e";
        dns = [ "10.64.0.1" ];
        mtu = 1380;
      };
      peer = {
        publicKey = "bZQF7VRDRK/JUJ8L6EFzF/zRw2tsqMRk6FesGtTgsC0=";
        endpointHost = "138.199.43.91";
        endpointPort = 51820;
      };
    };

    # Keep downloads and libraries on the HDD for hardlink imports. The
    # required mount prevents writes to root if the disk is absent or locked.
    storage = {
      rootDir = "/mnt/homelab/media";
      requiredMounts = [ "/mnt/homelab" ];
    };

    # Reserve headroom on the HDD for backup growth and imports.
    operations.pressure = {
      pauseBytes = 1024 * 1024 * 1024 * 1024;
      resumeBytes = 1152 * 1024 * 1024 * 1024;
    };
  };
}
