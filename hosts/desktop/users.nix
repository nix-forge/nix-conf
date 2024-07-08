{ lib, tree, ... }:
{
  imports =
    with lib.cust.nixos;
    let
      homes = tree.homes;
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
        homeManagerModules = homes.desktop.modules { inherit tree lib; };
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
