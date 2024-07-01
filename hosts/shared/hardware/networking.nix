{ self, lib, ... }:
{
  imports = [ self.nixOSModules.hardware.networking ];

  networking = {
    generateHostId = true;

    networkmanager = {
      enable = true;
      wifi.backend = "iwd";
    };

    enableIPv6 = false;

    dnscrypt-proxy.enable = true;

    # randomizeMacAddress = true;

    # global dhcp has been deprecated upstream
    # use the new networkd service instead of the legacy
    # "script-based" network setups. Host may contain individual
    # dhcp interfaces or systemd-networkd configurations in host
    # specific directories
    useDHCP = lib.mkForce false;
    # useNetworkd = lib.mkForce true;

    # set static IP address on wlan0
    interfaces.wlan0 = {
      ipv4.addresses = [
        {
          address = "192.168.1.2";
          prefixLength = 24;
        }
      ];
    };
    defaultGateway = {
      address = "192.168.1.1";
      interface = "wlan0";
    };

    stevenblack = {
      enable = true;
      block = [
        "fakenews"
        "gambling"
        "porn"
      ];
    };
  };
}
