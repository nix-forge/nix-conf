{ lib, ... }:
let
  privateIPv4 = "10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16";
in
{
  networking = {
    useDHCP = false;
    useNetworkd = true;
    networkmanager.enable = false;
    firewall = {
      # Keep the global SSH firewall integration disabled so it cannot add a
      # public port-22 rule ahead of these source-address restrictions.
      extraInputRules = ''
        ip saddr { ${privateIPv4} } tcp dport 22 accept comment "allow SSH from private IPv4 networks"
        ip6 saddr fc00::/7 tcp dport 22 accept comment "allow SSH from IPv6 ULA networks"
      '';
    };

    wireless.iwd = {
      enable = true;
      settings = {
        General = {
          Country = "US";
          EnableNetworkConfiguration = false;
          # Keep the adapter MAC stable on this trusted LAN. The desktop's
          # SSH and Sunshine clients intentionally use its DHCP identity; a
          # per-network randomized MAC would require matching router changes.
          AddressRandomization = "disabled";
        };
        IPv6.Enabled = true;
        Network.EnableIPv6 = true;
        Scan.DisablePeriodicScan = false;
        Settings.AutoConnect = true;
        DriverQuirks = {
          # This stationary, mains-powered desktop uses MediaTek's mt7921e
          # driver. Keep power save disabled to avoid added Wi-Fi latency and
          # throughput variation; RF retry rates are an AP/radio concern, not
          # something to mask with unsafe driver parameters.
          PowerSaveDisable = "mt7921e";
        };
      };
    };
  };

  services.resolved = {
    enable = true;
    settings.Resolve = {
      # Validate when the supplied resolver supports DNSSEC, without making
      # this home network unavailable when its router cannot validate it.
      DNSSEC = "allow-downgrade";
      # Resolve .local names without advertising this host. Avahi remains off,
      # so there is no mDNS listener or UDP/5353 firewall exception.
      LLMNR = "false";
      MulticastDNS = "resolve";
    };
  };
  services.avahi.enable = lib.mkForce false;
  services.openssh.openFirewall = lib.mkForce false;

  # This is a multi-homed client, not a router. Router Advertisements remain
  # enabled for IPv6 connectivity, but ICMP redirects are unnecessary and can
  # change routing policy on an untrusted or compromised LAN.
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;
  };

  systemd.network = {
    enable = true;
    # Both uplinks are intentionally non-blocking: Ethernet may be unplugged
    # and Wi-Fi may need time to scan.  A global wait-online service would
    # otherwise make activation fail even after connectivity has returned.
    wait-online.enable = false;
    networks = {
      "30-wired-networks" = {
        matchConfig.Name = [
          "en*"
          "eth*"
        ];
        # The desktop currently uses Wi-Fi. Do not make activation fail merely
        # because the optional Ethernet port is unplugged.
        linkConfig.RequiredForOnline = "no";
        networkConfig = {
          # UniFi supplies IPv4 through DHCP and IPv6 through router
          # advertisements.  Keep DHCPv6 disabled so a router advertisement
          # cannot start a second address-acquisition path unexpectedly.
          DHCP = "ipv4";
          IPv6AcceptRA = true;
          # systemd-networkd 261 can mark a link failed when adding a
          # temporary SLAAC address.  A prefix-stable RFC 7217 address keeps
          # the interface identifier private without using that path.
          IPv6PrivacyExtensions = false;
        };
        dhcpV4Config = {
          RouteMetric = 100;
          # Keep DHCP limited to addressing, routing, and DNS. Chrony owns
          # time sync; neither link may rename the host, install a global
          # search suffix, nor opt into a network-designated DNS resolver.
          SendHostname = false;
          UseHostname = false;
          UseNTP = false;
          UseDomains = "route";
          UseDNR = false;
        };
        ipv6AcceptRAConfig = {
          DHCPv6Client = false;
          RouteMetric = 100;
          Token = "prefixstable";
          UseDomains = "route";
          UseDNR = false;
          UseRedirect = false;
        };
      };

      "30-wireless-networks" = {
        matchConfig.WLANInterfaceType = "station";
        # A Wi-Fi scan can occasionally take more than a minute.  Do not
        # block the rest of boot while IWD is associating.
        linkConfig.RequiredForOnline = "no";
        networkConfig = {
          DHCP = "ipv4";
          IgnoreCarrierLoss = "3s";
          IPv6AcceptRA = true;
          IPv6PrivacyExtensions = false;
        };
        dhcpV4Config = {
          RouteMetric = 600;
          SendHostname = false;
          UseHostname = false;
          UseNTP = false;
          UseDomains = "route";
          UseDNR = false;
        };
        ipv6AcceptRAConfig = {
          DHCPv6Client = false;
          RouteMetric = 600;
          Token = "prefixstable";
          UseDomains = "route";
          UseDNR = false;
          UseRedirect = false;
        };
      };
    };
  };
}
