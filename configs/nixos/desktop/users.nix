{
  config,
  lib,
  tree,
  pkgs,
  ...
}:
let
  addUser = lib.cust.nixos.addUser { inherit config lib pkgs; };
  homes = name: tree.homes.${name}.modules;
in
lib.mkMerge [
  (addUser {
    username = "ianmh";
    description = "Ian Holloway";
    extraGroups = [
      "wheel"
      "audio"
      "video"
      "input"
      "docker"
      "libvirtd"
      "network"
      "networkmanager"
      "tss" # TPM
      "dialout" # serial devices
    ];
    initialPassword = "password";
    homeManagerModules = homes "desktop";
    shell = pkgs.nushell;
    uid = 1000;
  })
]
