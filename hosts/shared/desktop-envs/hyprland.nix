{
  useMainUser ? false,
  username ? null,
  ...
}: {
  lib,
  pkgs,
  config,
  inputs,
  self,
  ...
}: let
  # Define the user to use for home manager
  user =
    if useMainUser || username == null
    then config.users.mainUser
    else username;
  # Get the home manger config
  homeConfig = config.home-manager.users.${user};

  # Get the Hyprland package from home manager
  # NOTE: It is necessary to get the package from home manager because home manger can modify the base pacakge
  #       Also, ideally we only want to create one Hyprland session that multiple users can share. We need to choose
  #       a user who's Hyprland session will define all Hyprland sessions at login. Otherwise another way this could
  #       be done is to create a session for each user for a given session.
  hyprlandPkg = homeConfig.wayland.windowManager.hyprland.finalPackage;
in {
  imports = [
    # Add the session to NixOS
    # NOTE: This has to be done because Hyprland will be configured through home manager
    (lib.cust.nixos.addSession {
      inherit pkgs lib;
      name = "Hyprland";
      package = hyprlandPkg;
    })
  ];
}
