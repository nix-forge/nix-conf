{ inputs, ... }:
{
  imports = [
    inputs.hyprland.homeManagerModules.default
    ./config.nix
    # ./windowrules.nix
    ./keybinds.nix
    ./xdg.nix
  ];

  wayland.windowManager.hyprland.enable = true;
}
