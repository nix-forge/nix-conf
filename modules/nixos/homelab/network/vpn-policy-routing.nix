{ lib, config, ... }:
let
  cfg = config.homelab.network.vpnPolicyRouting;
  inherit (cfg) vpnInterface;
  vpnPeers = config.networking.wireguard.interfaces.${vpnInterface}.peers or [ ];
  inherit (cfg) vpnUsers;
  allowedIPv4Cidrs =
    cfg.allowedIPv4Cidrs
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
  inherit (cfg) allowedIPv6Cidrs;
  renderSet = values: "{ ${lib.concatStringsSep ", " values} }";
  routingTable = 51820;
  uidFor = user: lib.attrByPath [ user ] null cfg.vpnUserUids;
  primaryGroupFor = user: lib.attrByPath [ user ] user cfg.vpnUserPrimaryGroups;
  extraGroupsFor = user: lib.attrByPath [ user ] [ ] cfg.vpnUserExtraGroups;
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

    vpnUserUids = lib.mkOption {
      type = lib.types.attrsOf lib.types.int;
      default = {
        qbittorrent = 2001;
        nzbget = 2002;
        prowlarr = 2003;
      };
      description = "UID map used by nftables skuid rules for VPN-bound users.";
    };

    vpnUserPrimaryGroups = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        qbittorrent = "qbittorrent";
        nzbget = "nzbget";
        prowlarr = "prowlarr";
      };
      description = "Primary group map for VPN-bound service users.";
    };

    vpnUserExtraGroups = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = {
        qbittorrent = [ "downloads" ];
        nzbget = [ "downloads" ];
        prowlarr = [ ];
      };
      description = "Supplementary groups for VPN-bound users.";
    };

    downloadsGroup = lib.mkOption {
      type = lib.types.str;
      default = "downloads";
      description = "Shared downloads group for media ingest workflow.";
    };

    downloadsGroupGid = lib.mkOption {
      type = lib.types.int;
      default = 2010;
      description = "GID for shared downloads group.";
    };

    mediaGroup = lib.mkOption {
      type = lib.types.str;
      default = "media";
      description = "Shared media library group.";
    };

    mediaGroupGid = lib.mkOption {
      type = lib.types.int;
      default = 2000;
      description = "GID for shared media library group.";
    };

    allowedIPv4Cidrs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "127.0.0.0/8"
        "100.64.0.0/10"
        "169.254.0.0/16"
      ];
      description = "IPv4 CIDRs allowed to bypass VPN egress filtering for VPN-bound users.";
    };

    allowedIPv6Cidrs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "::1/128"
        "fd7a:115c:a1e0::/48"
        "fe80::/10"
      ];
      description = "IPv6 CIDRs allowed to bypass VPN egress filtering for VPN-bound users.";
    };
  };

  config = {
    assertions = [
      {
        assertion = builtins.all (user: uidFor user != null) vpnUsers;
        message = "Each homelab.network.vpnPolicyRouting.vpnUsers entry must exist in vpnUserUids.";
      }
    ];

    users.users = builtins.listToAttrs (
      map (user: {
        name = user;
        value = {
          isSystemUser = lib.mkDefault true;
          uid = lib.mkDefault (uidFor user);
          group = lib.mkDefault (primaryGroupFor user);
          extraGroups = lib.mkDefault (extraGroupsFor user);
        };
      }) vpnUsers
    );

    users.groups = {
      ${cfg.downloadsGroup}.gid = lib.mkDefault cfg.downloadsGroupGid;
      ${cfg.mediaGroup}.gid = lib.mkDefault cfg.mediaGroupGid;
    }
    // builtins.listToAttrs (
      map (user: {
        name = primaryGroupFor user;
        value = { };
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
  };
}
