{ lib, ... }:
let
  network = builtins.fromJSON (builtins.readFile ../../../../shared/local/network.json);
  sshClientCIDRs = "${network.trustedLanCIDR}, ${network.wireguardVpnCIDR}";
in
{
  networking = {
    useDHCP = false;
    useNetworkd = true;
    # The temporary GNOME compatibility layer defaults this on. Networkd owns
    # both links and IWD owns wireless association.
    networkmanager.enable = false;
    firewall = {
      # Keep the global SSH firewall integration disabled so it cannot add a
      # public port-22 rule ahead of these source-address restrictions.
      extraInputRules = ''
        iifname { "enp13s0", "wlan0" } ip saddr { ${sshClientCIDRs} } tcp dport 22 accept comment "allow SSH from trusted LAN and VPN"
        iifname { "enp13s0", "wlan0" } ip6 saddr fc00::/7 tcp dport 22 accept comment "allow SSH from ULA networks"
        iifname { "enp13s0", "wlan0" } ip saddr ${network.trustedLanCIDR} udp sport 5353 udp dport 5353 accept comment "allow LAN mDNS replies for MacBook lookup"
        iifname { "enp13s0", "wlan0" } ip6 saddr fe80::/10 udp sport 5353 udp dport 5353 accept comment "allow link-local mDNS replies for MacBook lookup"
      '';
    };

  };

  services.avahi.enable = lib.mkForce false;

  # Resolve the MacBook's Bonjour name without advertising desktop services.
  # Only the physical uplinks participate; guest bridges stay disabled.
  services.resolved.settings.Resolve.MulticastDNS = lib.mkForce "resolve";

  # Router Advertisements remain enabled for IPv6 connectivity, but ICMP
  # redirects are unnecessary and can change routing policy on a compromised LAN.
  boot.kernel.sysctl = {
    # Keep addresses on the same subnet from answering ARP on the other link.
    "net.ipv4.conf.all.arp_ignore" = 1;
    "net.ipv4.conf.all.arp_announce" = 2;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;
  };

  systemd.network = {
    enable = true;
    # Only homelab listeners wait for the wired address; a disconnected cable
    # or slow Wi-Fi scan must not hold up the rest of the desktop.
    wait-online.enable = false;
    networks = {
      "30-wired-networks" = {
        matchConfig.Name = "enp13s0";
        linkConfig.RequiredForOnline = "no";
        networkConfig = {
          MulticastDNS = "resolve";
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
          # time sync; DHCP may not rename the host, install a global
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
        linkConfig.RequiredForOnline = "no";
        networkConfig = {
          MulticastDNS = "resolve";
          DHCP = "ipv4";
          IgnoreCarrierLoss = false;
          IPv6AcceptRA = true;
          IPv6PrivacyExtensions = false;
        };
        dhcpV4Config = {
          RouteMetric = 600;
          SendHostname = false;
          UseHostname = false;
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
