{ lib, ... }:
{
  networking.firewall = {
    checkReversePath = lib.mkDefault "loose";
    allowPing = lib.mkForce false;
    trustedInterfaces = lib.mkDefault [ "lo" ];
    allowedTCPPorts = lib.mkDefault [ ];
    allowedUDPPorts = lib.mkDefault [ ];
  };
}
