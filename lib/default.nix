{lib, ...}: {
  NixOS = import ./NixOS;
  mkHost = import ./mkHost.nix;
  mkHome = import ./mkHome.nix;
  mkUser = import ./mkUser.nix;
}
