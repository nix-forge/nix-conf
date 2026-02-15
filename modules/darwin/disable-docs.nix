{ lib, ... }:
{
  programs.info.enable = lib.mkForce false;
  programs.man.enable = lib.mkForce false;
}
