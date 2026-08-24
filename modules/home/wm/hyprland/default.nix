{
  pkgs,
  lib,
  osConfig ? null,
  ...
}:
let
  nixosHyprland = osConfig != null && (osConfig.programs.hyprland.enable or false);
  withUWSM = if nixosHyprland then osConfig.programs.hyprland.withUWSM else false;
  usingUWSMHyprland = nixosHyprland && withUWSM;
in
{
  imports = [ (import ./xdg.nix { inherit nixosHyprland pkgs; }) ];

  wayland.windowManager.hyprland = {
    enable = true;
    # Hyprland 0.55+ reads `hyprland.lua`.
    configType = "lua";
    # Use the NixOS-provided compositor and portal when embedded in NixOS;
    # otherwise use the matching Nixpkgs packages.  This repository does not
    # carry a separate Hyprland flake input.
    package = if nixosHyprland then null else pkgs.hyprland;
    portalPackage = if nixosHyprland then null else pkgs.xdg-desktop-portal-hyprland;

    systemd = {
      enable = lib.mkForce (!usingUWSMHyprland);
      variables = [ "--all" ];
    };

  };
}
