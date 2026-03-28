{ lib, ... }:
{
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
}
