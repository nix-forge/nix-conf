{ modules, inputs, ... }:
{
  system = "x86_64-linux";
  hostName = "media-server";

  secrets = {
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO3PjFNVCaBfwUJIKjQeBoK2kz0VaLdNAQVUb5pJdPPf";
    groups = [ "IanHollow" ];
  };

  nixpkgsArgs = {
    config = {
      allowUnfree = true;
      allowUnfreePredicate = _: true;
      allowBroken = false;
    };
  };

  modules = with modules; [
    base-base
    registry
    boot
    agenix

    security
    server-ssh
    hardware-networking
    virtualisation-docker
    server-media

    inputs.srvos.nixosModules.server
    inputs.disko.nixosModules.disko

    ./hardware/disks.nix
    ./modules/site.nix
    ./modules/secrets.nix
    ./modules/exposure.nix
  ];
}
