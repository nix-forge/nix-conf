{
  profile ? "home-server",
}:
{ config, lib, ... }:
let
  stack = import ./stack-values.nix { inherit profile; };
  vpn = stack.vpn;

  useIPv4 = vpn.interfaceAddress4 != null;
  useIPv6 = vpn.interfaceAddress6 != null;

  family =
    if useIPv4 && useIPv6 then
      "both"
    else if useIPv4 then
      "ipv4"
    else if useIPv6 then
      "ipv6"
    else
      throw "vpn.interfaceAddress4 and vpn.interfaceAddress6 cannot both be null";

  renderSet = values: "{ ${lib.concatStringsSep ", " values} }";

  indexOf =
    needle: haystack:
    let
      go =
        idx: rest:
        if rest == [ ] then
          throw "User ${needle} not found in vpn.users"
        else if builtins.head rest == needle then
          idx
        else
          go (idx + 1) (builtins.tail rest);
    in
    go 0 haystack;

  wgAddresses =
    lib.optionals useIPv4 [ "${vpn.interfaceAddress4}/32" ]
    ++ lib.optionals useIPv6 [ "${vpn.interfaceAddress6}/128" ];

  peerAllowedIPs = lib.optionals useIPv4 [ "0.0.0.0/0" ] ++ lib.optionals useIPv6 [ "::/0" ];

  bypassIPv4Cidrs =
    vpn.bypassIPv4Cidrs or [
      "127.0.0.0/8"
      "169.254.0.0/16"
      # add your LAN here only if you intentionally want cleartext LAN access:
      # "192.168.1.0/24"
    ];

  bypassIPv6Cidrs =
    vpn.bypassIPv6Cidrs or [
      "::1/128"
      "fe80::/10"
      # add your ULA here only if you intentionally want cleartext LAN access:
      # "fd00::/8"
    ];

  mkUserRoutingRules =
    user:
    let
      basePriority = 30000 + (indexOf user vpn.users * 10);
    in
    [
      # First: let this user keep any specific non-default routes from main
      {
        User = user;
        Table = "main";
        SuppressPrefixLength = 0;
        Priority = basePriority;
        Family = family;
      }

      # Then: send the rest of this user's traffic through the WireGuard table
      {
        User = user;
        Table = vpn.table;
        Priority = basePriority + 1;
        Family = family;
      }
    ];

  mkKillSwitchRules = user: ''
    meta skuid ${user} oifname "${vpn.interface}" counter accept
    ${lib.optionalString useIPv4 ''
      meta skuid ${user} ip daddr ${renderSet bypassIPv4Cidrs} counter accept
    ''}
    ${lib.optionalString useIPv6 ''
      meta skuid ${user} ip6 daddr ${renderSet bypassIPv6Cidrs} counter accept
    ''}
    meta skuid ${user} counter drop
  '';

  routeHostDnsViaVpn = vpn.routeHostDnsViaVpn or true;
in
{
  assertions = [
    {
      assertion = lib.hasAttrByPath [ "age" "secrets" "mullvad-wg-private-key" ] config;
      message = "age.secrets.mullvad-wg-private-key must exist.";
    }
    {
      assertion = useIPv4 || useIPv6;
      message = "At least one of vpn.interfaceAddress4 or vpn.interfaceAddress6 must be set.";
    }
  ];

  networking.useNetworkd = lib.mkDefault true;
  services.resolved.enable = lib.mkDefault true;

  # NixOS wiki recommends loose rpfilter for WireGuard client setups.
  networking.firewall.checkReversePath = lib.mkDefault "loose";

  networking.nftables.enable = true;

  # Optional but nice: a readable name for the numeric table.
  systemd.network.config.routeTables.wg-services = vpn.table;

  systemd.network.netdevs."50-${vpn.interface}" = {
    netdevConfig = {
      Name = vpn.interface;
      Kind = "wireguard";
    };

    wireguardConfig = {
      PrivateKeyFile = config.age.secrets.mullvad-wg-private-key.path;
    };

    wireguardPeers = [
      {
        PublicKey = vpn.peer.publicKey;
        Endpoint = vpn.peer.endpoint;
        PersistentKeepalive = vpn.peer.persistentKeepalive;
        AllowedIPs = peerAllowedIPs;

        # Put the peer's full-tunnel routes only in this custom table.
        RouteTable = vpn.table;
      }
    ];
  };

  systemd.network.networks."50-${vpn.interface}" = {
    matchConfig.Name = vpn.interface;

    address = wgAddresses;

    # Recommended simple DNS mode:
    # route host DNS over the VPN link to avoid resolver leaks.
    dns = lib.mkIf routeHostDnsViaVpn vpn.dns;
    domains = lib.mkIf routeHostDnsViaVpn [ "~." ];
    networkConfig = lib.mkMerge [
      {
        ConfigureWithoutCarrier = true;
        IgnoreCarrierLoss = true;
      }
      (lib.mkIf routeHostDnsViaVpn { DNSDefaultRoute = true; })
    ];

    routingPolicyRules = lib.concatMap mkUserRoutingRules vpn.users;
  };

  networking.nftables.tables.vpn-services = {
    family = "inet";
    content = ''
      chain output_filter {
        type filter hook output priority filter;
        policy accept;

        ${lib.concatStringsSep "\n        " (map mkKillSwitchRules vpn.users)}
      }
    '';
  };

  # Defense in depth for qBittorrent.
  services.qbittorrent.serverConfig.Preferences.Connection = {
    Interface = vpn.interface;
  }
  // lib.optionalAttrs useIPv4 { InterfaceAddress = vpn.interfaceAddress4; };
}
