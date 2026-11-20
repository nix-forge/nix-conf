{ lib, pkgs, ... }: {
  imports = [ ../../../shared/local/nix-seal.nix ];
  # Install native SSH request workers beside nix-seal on the administrator,
  # and the matching operator commands on the desktop. No remote code payloads.
  home.packages = [
    (import ../../../../flake/runtime-packages.nix { inherit pkgs; }).homelabCredentials
  ];
  nixSeal = {
    publicKey = lib.removeSuffix "\n" (builtins.readFile ./identity.pub);
  };
}
