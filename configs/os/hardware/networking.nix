{
  self,
  lib,
  config,
  ...
}:
{
  imports = [ self.nixOSModules.hardware.networking ];

  networking = {
    generateHostId = true;

    networkmanager = {
      enable = true;
      wifi.backend = "iwd";
    };

    enableIPv6 = true;

    dnscrypt-proxy = {
      enable = true;
    };

    randomizeMacAddress = true;

    # global dhcp has been deprecated upstream
    # use the new networkd service instead of the legacy
    # "script-based" network setups. Host may contain individual
    # dhcp interfaces or systemd-networkd configurations in host
    # specific directories
    useDHCP = lib.mkForce false;
    useNetworkd = lib.mkForce false;

    # set static IP address on wlan0
    # interfaces.wlan0 = {
    #   ipv4.addresses = [
    #     {
    #       address = "192.168.1.2";
    #       prefixLength = 24;
    #     }
    #   ];
    # };
    # defaultGateway = {
    #   address = "192.168.1.1";
    #   interface = "wlan0";
    # };

    stevenblack = {
      enable = true;
      block = [
        "fakenews"
        "gambling"
        "porn"
      ];
    };
  };

  systemd.network = {
    enable = true;

    links."30-wireless-networks" = {
      matchConfig.WLANInterfaceType = "station";
      linkConfig = lib.mkIf config.networking.randomizeMacAddress { MACAddressPolicy = "random"; };
    };

    networks."30-wireless-networks" = {
      matchConfig.WLANInterfaceType = "station";
      networkConfig =
        {
          # start a DHCP Client for Addressing/Routing
          DHCP = if config.networking.enableIPv6 then "yes" else "ipv4";
          # accept Router Advertisements for Stateless IPv6 Autoconfiguraton (SLAAC)
          IPv6AcceptRA = config.networking.enableIPv6;
        }
        // (lib.optionalAttrs (config.networking.enableIPv6) {
          # Enable IPv6 Privacy Extensions
          # This config option is based on Official NixOS options
          IPv6PrivacyExtensions = "kernel";

        });

      linkConfig = {
        # make routing on this interface a dependency for network-online.target
        RequiredForOnline = "routable";
      };

      dhcpV4Config =
        {
          # Make ipv4 dhcp client use the mac address as client identifier
          ClientIdentifier = "mac";
          # Use DNS Servers from DHCP if dnscrypt-proxy is disabled
          UseDNS = if config.networking.dnscrypt-proxy.enable then false else true;
          # Set the DUID type to link-layer to use the MAC address as DUID
          DUIDType = "link-layer";
          # # Route Metric is default 1024 so 1025 will mathat if ethernet is connected it will be preferred
          # RouteMetric = 1025;
        }
        # Make networkd follow Anonymization Standards. Only can be true MACAddressPolicy is "random"
        // (lib.optionalAttrs (config.networking.randomizeMacAddress) { Anonymize = true; });

      # set the route metric to the same as the ipv4 route metric
      # ipv6AcceptRAConfig.RouteMetric = 1025;

      dhcpV6Config = lib.mkIf config.networking.enableIPv6 {
        # Use DNS Servers from DHCP if dnscrypt-proxy is disabled
        UseDNS = if config.networking.dnscrypt-proxy.enable then false else true;
        # Set the DUID type to link-layer to use the MAC address as DUID
        DUIDType = "link-layer";
      };
    };
  };
}
