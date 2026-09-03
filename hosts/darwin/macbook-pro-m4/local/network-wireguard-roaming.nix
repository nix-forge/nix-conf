{ config, ... }: {
  networking.wg-quick.interfaces.home-vpn = {
    autostart = false;
    address = [ "192.168.3.3/32" ];
    dns = [ "192.168.3.1" ];
    privateKeyFile = config.nixSeal.secrets."wireguard-home-private-key".path;
    peers = [
      {
        publicKey = "1qDQ0Hfrzq7/37NtAf7q61MDVKPB+cUUVao85fh5/xY=";
        allowedIPs = [ "0.0.0.0/0" ];
        endpoint = "ddns.ianholloway.com:51820";
      }
    ];
  };

  services.wireguardRoaming = {
    enable = true;
    interfaceName = "home-vpn";

    # This host is self-contained. No background policy service or another
    # machine decides whether the VPN should be connected.
    autoConnect = false;

    # The UniFi profile has only an IPv4 default route. Block IPv6 only while
    # the tunnel is connected so traffic cannot bypass the home egress.
    ipv6Policy = "block-while-connected";
    reconcileIntervalSeconds = 15;
    activationTimeoutSeconds = 15;
  };
}
