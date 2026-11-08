{ pkgs, desktop }:
let
  inherit (pkgs) lib;
  failsWith =
    fragment: module:
    let
      assertions = (desktop.extendModules { modules = [ module ]; }).config.assertions;
    in
    lib.any (item: !item.assertion && lib.hasInfix fragment item.message) assertions;
  valid = lib.all (item: item.assertion) desktop.config.assertions;
  contracts = [
    valid
    # A VPN peer admitted by HTTPS must also remain local to Jellyfin's API.
    (lib.all (
      cidr: builtins.elem cidr desktop.config.homelab.integrations.jellyfin.network.localNetworkSubnets
    ) desktop.config.homelab.operations.lanHttps.allowedCIDRs)
    (lib.all
      (
        name:
        lib.all
          (
            family:
            builtins.elem family desktop.config.systemd.services.${name}.serviceConfig.RestrictAddressFamilies
          )
          [
            "AF_INET"
            "AF_INET6"
            "AF_UNIX"
            "AF_NETLINK"
          ]
      )
      [
        "prowlarr"
        "sonarr"
        "radarr"
        "lidarr"
        "seerr"
        "bazarr"
      ]
    )
    (failsWith "Desktop qBittorrent must remain" {
      homelab.apps.qbittorrent.vpn.enable = lib.mkForce false;
    })
    (failsWith "VPN-confined qBittorrent must bind" {
      homelab.apps.qbittorrent.bindAddress = lib.mkForce "169.254.1.2";
    })
    (failsWith "qbittorrent must run" { systemd.services.qbittorrent.vpn.enable = lib.mkForce false; })
    (failsWith "slskd must run" {
      homelab.apps.slskd.vpn.enable = lib.mkForce false;
      homelab.apps.slskd.vpn.allowUnconfined = true;
    })
    (failsWith "Aurral must run" { systemd.services.aurral.vpn.enable = lib.mkForce false; })
    (failsWith "Aurral API bridges must preserve" {
      systemd.services.aurral-lidarr-vpn.vpn.enable = lib.mkForce false;
    })
    (failsWith "Aurral API bridges must preserve" {
      systemd.services.aurral-http-host.serviceConfig.IPAddressDeny = lib.mkForce [ ];
    })
    (failsWith "Aurral API bridges must preserve" {
      systemd.services.aurral-library-rescan.serviceConfig.IPAddressDeny = lib.mkForce [ ];
    })
    (failsWith "qBittorrent must bind" {
      services.qbittorrent.serverConfig.BitTorrent.Session.Interface = lib.mkForce "";
    })
    (failsWith "stop at download completion" {
      services.qbittorrent.serverConfig.BitTorrent.Session.GlobalMaxRatio = lib.mkForce (-1);
    })
    (failsWith "Media acquisition requires" {
      services.vpnConfinement.namespaces.vpnapps.dns.allowHostResolverIPC = lib.mkForce true;
    })
    (failsWith "networking.dnsBlocker requires" {
      networking.dnsBlocker.upstreams = lib.mkForce [ "1.1.1.1" ];
    })
    (failsWith "prowlarr must block direct Internet" {
      systemd.services.prowlarr.serviceConfig.IPAddressDeny = lib.mkForce [ ];
    })
    (failsWith "sonarr must deny private networks" {
      systemd.services.sonarr.serviceConfig.IPAddressDeny = lib.mkForce [ ];
    })
    (failsWith "tagged VPN proxy only" {
      homelab.integration.services.prowlarr.extraSettings.hostProxy.enabled = lib.mkForce true;
    })
    (failsWith "FlareSolverr needs a reviewed" {
      homelab = {
        optional.apps.flaresolverr.enable = lib.mkForce true;
        integrations.prowlarr = {
          privateIndexersFile = lib.mkForce null;
          indexers = lib.mkForce { };
        };
      };
    })
    (failsWith "Each enabled Prowlarr indexer needs one explicit route tag" {
      homelab.integrations.prowlarr.indexers.noRoute.implementation = "Torznab";
    })
  ];
in
assert lib.assertMsg (lib.all (
  x: x
) contracts) "Desktop homelab VPN policy did not reject an unsafe configuration.";
pkgs.runCommand "homelab-vpn-policy" { } "touch $out"
