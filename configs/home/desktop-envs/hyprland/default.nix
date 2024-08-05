{ inputs, ... }:
{
  imports = [
    ./config.nix
    ./windowrules.nix
    ./keybinds.nix
    ./xdg.nix
  ];

  wayland.windowManager.hyprland.enable = true;
}
