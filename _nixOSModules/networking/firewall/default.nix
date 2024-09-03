{
  pkgs,
  lib,
  config,
  ...
}:
# let
#   cfg = config.networking.nftables;
# in
{
  imports = [
    # TODO: ./nftables

    # TODO: ./fail2ban.nix
  ];

  config = {
    # enable opensnitch firewall
    # inactive until opensnitch UI is opened
    # services.opensnitch.enable = true;

    networking.firewall = {
      enable = true;
      package = pkgs.iptables;
      allowedTCPPorts = [
        443 # HTTPS
      ];
      allowedUDPPorts = [ ];
      logReversePathDrops = true;
      logRefusedConnections = false; # avoid log spam
      checkReversePath = lib.mkForce false; # Don't filter DHCP packets, according to nixops-libvirtd
    };
  };
}
