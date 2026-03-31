{ lib, ... }:
{
  networking.wireguard = {
    enable = lib.mkDefault true;
    useNetworkd = lib.mkDefault true;
  };

  services.resolved.enable = lib.mkDefault true;
}
