{ modules, inputs, ... }:
{
  system = "x86_64-linux";
  hostName = "home-server";

  secrets = {
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO3PjFNVCaBfwUJIKjQeBoK2kz0VaLdNAQVUb5pJdPPf";
    extraPublicKeys = [ ];
    groups = [ "IanHollow" ];
  };

  nixpkgsArgs = {
    config = {
      allowUnfree = true;
      allowUnfreePredicate = _: true;
    };
  };

  modules = with modules; [
    meta
    agenix
    determinate
    nix-settings

    users

    inputs.srvos.nixosModules.server
    inputs.srvos.nixosModules.mixins-nix-experimental

    boot
    boot-grub
    boot-grub-server

    # homelab

    {
      virtualisation.vmVariant = {
        virtualisation = {
          memorySize = 4096;
          cores = 4;
          diskSize = 32768;
        };
      };
    }

    inputs.disko.nixosModules.disko
    ./modules/storage.nix
  ];
}
