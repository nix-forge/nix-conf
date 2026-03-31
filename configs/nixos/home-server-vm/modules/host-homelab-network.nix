{ config, lib, ... }:
{
  assertions = [
    {
      assertion = lib.hasAttrByPath [ "age" "secrets" "mullvad-wg-private-key" ] config;
      message = "age.secrets.mullvad-wg-private-key must exist for host-homelab-network.";
    }
  ];

  networking.wireguard.interfaces.wg-mullvad = {
    privateKeyFile = config.age.secrets.mullvad-wg-private-key.path;
    ips = [
      "10.71.216.231/32"
      "fc00:bbbb:bbbb:bb01::8:d8e6/128"
    ];
    allowedIPsAsRoutes = false;
    peers = [
      {
        publicKey = "bZQF7VRDRK/JUJ8L6EFzF/zRw2tsqMRk6FesGtTgsC0=";
        endpoint = "138.199.43.91:51820";
        allowedIPs = [
          "0.0.0.0/0"
          "::/0"
        ];
        persistentKeepalive = 25;
      }
    ];
  };

  systemd.network.networks."40-wg-mullvad".dns = [ "10.64.0.1" ];

  homelab.network.vpnPolicyRouting = {
    vpnUsers = [
      "qbittorrent"
      "nzbget"
      "prowlarr"
    ];
    vpnUserUids = {
      qbittorrent = 2001;
      nzbget = 2002;
      prowlarr = 2003;
    };
  };

  users.users.qbittorrent = {
    isSystemUser = lib.mkDefault true;
    uid = lib.mkDefault 2001;
    group = lib.mkDefault "qbittorrent";
  };

  users.users.nzbget = {
    isSystemUser = lib.mkDefault true;
    uid = lib.mkDefault 2002;
    group = lib.mkDefault "nzbget";
  };

  users.users.prowlarr = {
    isSystemUser = lib.mkDefault true;
    uid = lib.mkDefault 2003;
    group = lib.mkDefault "prowlarr";
  };

  users.groups.qbittorrent = { };
  users.groups.nzbget = { };
  users.groups.prowlarr = { };

  services.qbittorrent.serverConfig.Preferences.Connection = {
    Interface = "wg-mullvad";
    InterfaceAddress = "10.71.216.231";
  };
}
