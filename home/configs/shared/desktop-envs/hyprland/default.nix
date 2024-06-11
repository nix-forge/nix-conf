{
  self,
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    inputs.hyprland.homeManagerModules.default
    ./config.nix
    # ./windowrules.nix
    ./keybinds.nix
    ./xdg.nix
  ];

  home.packages = [
    # xwayland perm for pkexec
    pkgs.xorg.xhost
  ];

  wayland.windowManager.hyprland = {
    enable = true;

    settings.exec-once = [
      # allow apps with risen perms after agent to connect to local xwayland
      "${lib.getExe pkgs.xorg.xhost} +local:"
    ];
  };
}
