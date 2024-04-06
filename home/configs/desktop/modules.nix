{ tree, ... }:
with tree.home.configs.shared;
[
  wayland.default
  wayland.env.nvidia
  theming.basic.default
  profile
]
