{ lib, ... }:
let
  privateIPv4 = "10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16";
in
{
  networking = {
    useDHCP = false;
    useNetworkd = true;
    # The temporary GNOME compatibility layer defaults this on. This desktop's
    # physical links are intentionally owned by systemd-networkd + IWD until a
    # separately tested NetworkManager migration replaces their profiles.
    networkmanager.enable = false;
    firewall = {
      # Keep the global SSH firewall integration disabled so it cannot add a
      # public port-22 rule ahead of these source-address restrictions.
      extraInputRules = ''
        ip saddr { ${privateIPv4} } tcp dport 22 accept comment "allow SSH from private IPv4 networks"
        ip6 saddr fc00::/7 tcp dport 22 accept comment "allow SSH from IPv6 ULA networks"
      '';
    };

  };

  services.avahi.enable = lib.mkForce false;

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
          # Blocky is the explicitly configured DNS policy point. Do not let
          # DHCP inject a per-link resolver that systemd-resolved can prefer
          # over its loopback-only Blocky upstream.
          UseDNS = false;
          UseNTP = false;
          UseDomains = "route";
          UseDNR = false;
        };
        ipv6AcceptRAConfig = {
          DHCPv6Client = false;
          RouteMetric = 100;
          Token = "prefixstable";
          UseDomains = "route";
          UseDNS = false;
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
          # See the wired profile: all ordinary DNS must traverse the local
          # Blocky service, while router advertisements still supply routing.
          UseDNS = false;
          UseNTP = false;
          UseDomains = "route";
          UseDNR = false;
        };
        ipv6AcceptRAConfig = {
          DHCPv6Client = false;
          RouteMetric = 600;
          Token = "prefixstable";
          UseDomains = "route";
          UseDNS = false;
          UseDNR = false;
          UseRedirect = false;
        };
      };
    };
  };
}
