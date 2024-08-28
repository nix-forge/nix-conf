{
  lib,
  tree,
  pkgs,
  inputs,
  ...
}:
{
  imports =
    with lib.cust.nixos;
    let
      homes =
        name:
        tree.homes.${name}.modules {
          inherit
            tree
            lib
            inputs
            pkgs
            ;
        };
    in
    [
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
        homeManagerModules = homes "desktop";
      })

      # (addUser {
      #   username = "guest";
      #   description = "Guest User";
      #   extraGroups = [
      #     "audio"
      #     "video"
      #   ];
      #   initialPassword = "password";
      #   homeManagerModules = homeConfigs.desktop.modules { inherit tree; };
      # })
    ];
}
