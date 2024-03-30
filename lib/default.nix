{lib, ...}: {
  nixos = import ./nixos;
  mkHost = import ./mkHost.nix;
  mkHome = import ./mkHome.nix;
  mkUser = import ./mkUser.nix;
}
