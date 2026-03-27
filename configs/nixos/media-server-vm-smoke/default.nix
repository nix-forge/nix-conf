{ modules, inputs, ... }:
{
  system = "aarch64-linux";
  hostName = "media-server-vm-smoke";

  secrets = {
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIWJYXhsmU3IU+wIX5aF7rwb6ckGu8WZSGWh250e4gO6";
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
    ../media-server-vm-parity/modules/vm-overrides.nix
    ./modules/vm-runtime.nix
  ];
}
