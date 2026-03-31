{ modules, inputs, ... }:
{
  system = "aarch64-linux";
  hostName = "home-server-vm";

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
    inputs.srvos.nixosModules.server

    meta
    agenix
    determinate
    nix-settings

    disko
    users
    vm
    vm-boot
    ./modules/host-homelab-storage.nix
    ./modules/host-homelab-network.nix
    ./modules/host-homelab-ingress.nix

    boot
    boot-grub
    boot-grub-server
    boot-encrypted-root
    storage-disko-luks-btrfs
    storage-btrfs
    storage-ssd
    hardware-tpm

    homelab-network
    homelab-proxy
    homelab-security
    homelab-media
    homelab-apps

    ./modules/vmAccess.nix
  ];
}
