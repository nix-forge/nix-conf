{ lib, config, ... }:
{
  assertions = [
    {
      assertion = lib.hasAttrByPath [ "age" "secrets" "mullvad-wg-private-key" ] config;
      message = "age.secrets.mullvad-wg-private-key must exist when importing homelab.network.mullvad-wireguard.";
    }
  ];

  networking.wireguard = {
    enable = true;
    useNetworkd = true;
    interfaces.wg-mullvad = {
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
  };

  services.resolved.enable = true;

  systemd.network.networks."40-wg-mullvad" = {
    dns = [ "10.64.0.1" ];
  };
}
