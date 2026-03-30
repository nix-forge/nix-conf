{ lib, config, ... }:
let
  cfg = config.homelab.network.vpnPolicyRouting;
  inherit (cfg) vpnInterface;
  vpnPeers = config.networking.wireguard.interfaces.${vpnInterface}.peers or [ ];
  inherit (cfg) vpnUsers;
  allowedIPv4Cidrs = [
    "127.0.0.0/8"
    "10.0.0.0/8"
    "172.16.0.0/12"
    "192.168.0.0/16"
    "100.64.0.0/10"
    "169.254.0.0/16"
  ]
  ++ map (addr: "${addr}/32") (
    builtins.filter (addr: addr != null) (
      map (
        peer:
        let
          endpoint = peer.endpoint or "";
          ipv4Match = builtins.match "([^:]+):[0-9]+" endpoint;
        in
        if ipv4Match == null then null else builtins.elemAt ipv4Match 0
      ) vpnPeers
    )
  );
  allowedIPv6Cidrs = [
    "::1/128"
    "fc00::/7"
    "fe80::/10"
  ];
  renderSet = values: "{ ${lib.concatStringsSep ", " values} }";
  routingTable = 51820;
  uidFor =
    user:
    let
      uid = lib.attrByPath [ "users" "users" user "uid" ] null config;
    in
    if uid == null then
      throw "homelab.network.vpnPolicyRouting: users.users.${user}.uid must be set for nftables skuid rules"
    else
      uid;
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
  options.homelab.network.vpnPolicyRouting = {
    vpnInterface = lib.mkOption {
      type = lib.types.str;
      default = "wg-mullvad";
      description = "WireGuard interface used for VPN policy routing.";
    };

    vpnUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "qbittorrent"
        "nzbget"
        "prowlarr"
      ];
      description = "System users that must route through the VPN table.";
    };

    sharedGroup = lib.mkOption {
      type = lib.types.str;
      default = "media";
      description = "Primary group assigned to VPN-bound service users.";
    };

    sharedGroupGid = lib.mkOption {
      type = lib.types.int;
      default = 2000;
      description = "GID for shared media access group used by VPN-bound users.";
    };
  };

  config = {
    assertions = [
      {
        assertion = builtins.all (
          user: lib.attrByPath [ "users" "users" user "uid" ] null config != null
        ) vpnUsers;
        message = "Each homelab.network.vpnPolicyRouting.vpnUsers entry must have users.users.<name>.uid set.";
      }
    ];

    users.users = builtins.listToAttrs (
      map (user: {
        name = user;
        value = {
          isSystemUser = lib.mkDefault true;
          uid = lib.mkDefault (2001 + indexOf user vpnUsers);
          group = lib.mkDefault cfg.sharedGroup;
        };
      }) vpnUsers
    );

    users.groups.${cfg.sharedGroup}.gid = lib.mkDefault cfg.sharedGroupGid;

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
  };
}
