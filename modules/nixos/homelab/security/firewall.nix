{ lib, ... }:
{
  networking.firewall = {
    enable = true;
    # Keep reverse path filtering loose for asymmetric policy routing:
    # traffic from VPN-routed service users (table 51820) and tailscale0 can
    # legitimately return via a different interface/path than the default table.
    checkReversePath = "loose";
    allowPing = lib.mkForce false;
    trustedInterfaces = [ "lo" ];
    allowedTCPPorts = [ ];
    allowedUDPPorts = [ ];
    interfaces.tailscale0.allowedTCPPorts = [
      22
      443
    ];
    interfaces.tailscale0.allowedUDPPorts = [ ];
  };
}
