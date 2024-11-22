{
  config,
  lib,
  tree,
  ...
}:
let
  addUser = lib.cust.nixos.addUser { inherit config lib; };
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
    ];
    initialPassword = "password";
    homeManagerModules = homes "laptop";
  })
]
