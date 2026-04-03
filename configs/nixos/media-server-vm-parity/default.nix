{ modules, inputs, ... }:
{
  system = "x86_64-linux";
  hostName = "media-server-vm-parity";

  secrets = {
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIYXqoCXD8+NQopmMXG0VJ1VkqkXUqFGwIYyR7b8kliA";
    extraPublicKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO3PjFNVCaBfwUJIKjQeBoK2kz0VaLdNAQVUb5pJdPPf"
    ];
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

    ../media-server/modules/site.nix
    ../media-server/modules/secrets.nix
    ../media-server/modules/exposure.nix
    ./modules/vm-common.nix
    ./modules/vm-runtime.nix
  ];
}
