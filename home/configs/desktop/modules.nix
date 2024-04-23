{ tree, ... }:
with tree.home.configs.shared;
[
  theming.basic.default

  desktop-envs.hyprland.default
  programs.rofi
  programs.waybar.default
  ./hyprland

  profile
]
