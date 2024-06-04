{ tree, lib, ... }:
let
  private = lib.bird.importDir ./private null;
in
with tree.home.configs.shared;
[
  theming.basic.default

  desktop-envs.hyprland.default
  programs.rofi
  programs.waybar.default
  ./hyprland

  { home.sessionVariables = lib.cust.env.wayland.all; }

  # private imports
  private.services

  profile
]
