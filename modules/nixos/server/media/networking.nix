{ config, lib, ... }:
let
  cfg = config.my.media;
in
{
  config = lib.mkIf (cfg.enable && cfg.network.manageHostNetworking) {
    networking = {
      useNetworkd = true;
      useDHCP = false;
      nftables.enable = true;
      firewall.interfaces.${cfg.network.interface} = {
        allowedTCPPorts = [ cfg.ports.ssh ];
        allowedUDPPorts = [ ];
      };
      inherit (cfg.network) nameservers;
    };

    systemd.network = {
      enable = true;
      networks."10-lan" = {
        matchConfig.Name = cfg.network.interface;
        address = [ "${cfg.network.lanAddress}/${toString cfg.network.lanPrefixLength}" ];
        networkConfig = {
          DHCP = "no";
          IPv6AcceptRA = cfg.network.enableIPv6;
        };
      };
    };
  };
}
