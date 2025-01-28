{
  moduleName ? "custom",
  randomizeMacAddress ? false,
}:
{ lib, config, ... }:
let
  cfg = config.networking.${moduleName}.networkd-general;
in
{
  options.networking.${moduleName}.networkd-general = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable a general networkd config.
        This config will work with other custom network modules but, it will not strictly rely on them.
      '';
    };
    wi-fi = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable WiFi Support";
      };
    };
    ethernet = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Ethernet Support";
      };
    };
  };

  config =
    let
      wifi-ethernet-priority-num = builtins.toString 30;

      links = {
        linkConfig = lib.mkIf randomizeMacAddress {
          MACAddressPolicy = "random";
        };
      };

      networks =
        let
          inherit (config.networking) enableIPv6;
          dnscrypt-proxy-enabled = config.services.dnscrypt-proxy2.enable;
        in
        {
          # start a DHCP Client for Addressing/Routing
          DHCP = if enableIPv6 then "yes" else "ipv4";

          networkConfig =
            {
              # accept Router Advertisements for Stateless IPv6 Autoconfiguraton (SLAAC)
              IPv6AcceptRA = enableIPv6;
            }
            // (lib.optionalAttrs enableIPv6 {
              # Enable IPv6 Privacy Extensions
              # This config option is based on Official NixOS options
              IPv6PrivacyExtensions = "kernel";
            });

          linkConfig = {
            # make routing on this interface a dependency for network-online.target
            RequiredForOnline = "routable";
          };

          dhcpV4Config = {
            # Make ipv4 dhcp client use duid  as client identifier
            ClientIdentifier = "duid";
            # Use DNS Servers from DHCP if dnscrypt-proxy is disabled
            UseDNS = if dnscrypt-proxy-enabled then false else true;
            # Set the DUID type to link-layer to use the MAC address as DUID
            DUIDType = "link-layer";
          };

          dhcpV6Config = lib.mkIf enableIPv6 {
            # Use DNS Servers from DHCP if dnscrypt-proxy is disabled
            UseDNS = if dnscrypt-proxy-enabled then false else true;
            # Set the DUID type to link-layer to use the MAC address as DUID
            DUIDType = "link-layer";
          };

          ipv6AcceptRAConfig = lib.mkIf enableIPv6 {
            # Use DNS Servers from DHCP if dnscrypt-proxy is disabled
            UseDNS = if dnscrypt-proxy-enabled then false else true;
          };
        };
    in
    lib.mkIf (cfg.enable) (
      lib.mkMerge [
        # General
        {
          # Disable default networkd
          networking.useNetworkd = lib.mkForce false;

          systemd.network = {
            enable = true;

            # Wait for one interface to be online to be considered online
            wait-online.anyInterface = true;
          };
        }

        # WiFi
        (lib.mkIf (cfg.wi-fi.enable) {
          systemd.network =
            let
              configBaseName = "${wifi-ethernet-priority-num}-wireless-networks";
              matchConfig.WLANInterfaceType = "station";
            in
            {
              links.${configBaseName} = {
                inherit matchConfig;
                inherit (links) linkConfig;
              };
              networks.${configBaseName} =
                {
                  inherit matchConfig;
                  inherit (networks)
                    DHCP
                    networkConfig
                    linkConfig
                    dhcpV4Config
                    dhcpV6Config
                    ipv6AcceptRAConfig
                    ;
                }
                // {
                  # Set route metric to 600 which is higher than than ethernet which will be 100
                  dhcpV4Config.RouteMetric = 600;
                  ipv6AcceptRAConfig.RouteMetric = 600;

                  # IgnoreCarrierLoss=3s ensures that systemd-networkd will not re-configure
                  # the interface (e.g., release and re-acquire a DHCP lease) for a short
                  # period (3 seconds in this example) while the wireless interface roams
                  # to another access point within the same wireless network (SSID), which
                  # translates to shorter downtime when roaming.
                  networkConfig.IgnoreCarrierLoss = "3s";
                };
            };
        })

        # Ethernet
        (lib.mkIf (cfg.ethernet.enable) {
          systemd.network =
            let
              configBaseName = "${wifi-ethernet-priority-num}-wired-networks";
              matchConfig.Name = [
                "en*"
                "eth*"
              ];
            in
            {
              links.${configBaseName} = {
                inherit matchConfig;
                inherit (links) linkConfig;
              };
              networks.${configBaseName} =
                {
                  inherit matchConfig;
                  inherit (networks)
                    DHCP
                    networkConfig
                    linkConfig
                    dhcpV4Config
                    dhcpV6Config
                    ipv6AcceptRAConfig
                    ;
                }
                // {
                  # Set route metric to 100 which is lower than than wifi which will be 600
                  dhcpV4Config.RouteMetric = 100;
                  ipv6AcceptRAConfig.RouteMetric = 100;
                };
            };
        })
      ]
    );
}
