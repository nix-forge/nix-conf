{ lib, ... }:
let
  vpnInterface = "wg-mullvad";
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
  allowedIPv4Cidrs = [
    "127.0.0.0/8"
    "10.0.0.0/8"
    "172.16.0.0/12"
    "192.168.0.0/16"
    "100.64.0.0/10"
    "169.254.0.0/16"
  ];
  allowedIPv6Cidrs = [
    "::1/128"
    "fc00::/7"
    "fe80::/10"
  ];
  renderSet = values: "{ ${lib.concatStringsSep ", " values} }";
  routingTable = 51820;
  uidFor = user: lib.attrByPath [ user ] 3000 vpnUserUids;
  indexOf =
    needle: haystack:
    let
      go =
        idx: rest:
        if rest == [ ] then
          0
        else if builtins.head rest == needle then
          idx
        else
          go (idx + 1) (builtins.tail rest);
    in
    go 0 haystack;
  mkUserRoutingRules =
    user:
    let
      userIndex = indexOf user vpnUsers;
      basePriority = 10000 + (userIndex * 10);
      userName = user;
    in
    [
      {
        Priority = basePriority;
        Family = "ipv4";
        User = userName;
        Table = "main";
        SuppressPrefixLength = 0;
      }
      {
        Priority = basePriority + 1;
        Family = "ipv6";
        User = userName;
        Table = "main";
        SuppressPrefixLength = 0;
      }
      {
        Priority = basePriority + 2;
        Family = "ipv4";
        User = userName;
        Table = toString routingTable;
      }
      {
        Priority = basePriority + 3;
        Family = "ipv6";
        User = userName;
        Table = toString routingTable;
      }
    ];
  drop4For =
    user:
    ''meta skuid ${toString (uidFor user)} oifname != "${vpnInterface}" ip daddr != ${renderSet allowedIPv4Cidrs} drop'';
  drop6For =
    user:
    ''meta skuid ${toString (uidFor user)} oifname != "${vpnInterface}" ip6 daddr != ${renderSet allowedIPv6Cidrs} drop'';
in
{
  users.users = builtins.listToAttrs (
    map (user: {
      name = user;
      value = {
        isSystemUser = lib.mkDefault true;
        uid = lib.mkDefault (uidFor user);
        group = lib.mkDefault "media";
      };
    }) vpnUsers
  );

  networking.nftables.enable = true;

  networking.nftables.tables.homelab-vpn = {
    family = "inet";
    content = ''
      chain output_filter {
        type filter hook output priority filter;
        policy accept;
        ${lib.concatStringsSep "\n        " (map drop4For vpnUsers)}
        ${lib.concatStringsSep "\n        " (map drop6For vpnUsers)}
      }
    '';
  };

  systemd.network.config.routeTables.homelab-vpn = routingTable;

  systemd.network.networks."40-${vpnInterface}" = {
    routes = [
      {
        Destination = "0.0.0.0/0";
        Table = toString routingTable;
      }
      {
        Destination = "::/0";
        Table = toString routingTable;
      }
    ];

    routingPolicyRules = lib.concatMap mkUserRoutingRules vpnUsers;
  };
}
