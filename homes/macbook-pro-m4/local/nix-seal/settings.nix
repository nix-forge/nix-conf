{ lib, pkgs, ... }: {
  imports = [ ../../../shared/local/nix-seal.nix ];
  # Install native SSH request workers beside nix-seal on the administrator,
  # and the matching operator commands on the desktop. No remote code payloads.
  home.packages = [
    (import ../../../../flake/runtime-packages.nix { inherit pkgs; }).homelabCredentials
  ];
  nixSeal = {
    publicKey = lib.removeSuffix "\n" (builtins.readFile ./identity.pub);
    secrets.desktop-homelab-hdd-recovery-key = {
      source = "homes/macbook-pro-m4/local/secrets/desktop-homelab-hdd-recovery-key.age";
      mode = "0600";
      phase = "services";
    };
  };
}
