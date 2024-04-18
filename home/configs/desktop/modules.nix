{ tree, ... }:
with tree.home.configs.shared;
[
  wayland.default
  wayland.env.nvidia
  theming.basic.default

  desktop-envs.hyprland.default
  ./hyprland

  profile
]
