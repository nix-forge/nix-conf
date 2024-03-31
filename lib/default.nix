{ lib, ... }:
{
  nixos = import ./nixos;
  mkHome = import ./mkHome.nix;
  mkHost = import ./mkHost.nix;
}
