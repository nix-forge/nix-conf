{ lib, ... }:
{
  networking.firewall = {
    enable = true;
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
