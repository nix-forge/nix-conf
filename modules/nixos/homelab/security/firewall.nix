{ lib, ... }:
{
  networking.firewall = {
    enable = true;
    # Keep reverse path filtering loose for asymmetric policy routing.
    checkReversePath = "loose";
    allowPing = lib.mkForce false;
    trustedInterfaces = [ "lo" ];
    allowedTCPPorts = [ ];
    allowedUDPPorts = [ ];
  };
}
