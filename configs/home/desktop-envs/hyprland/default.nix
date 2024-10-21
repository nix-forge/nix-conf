{
  inputs,
  pkgs,
  lib,
  config,
  ...
}:
{
  imports = [
    ./config.nix
    ./windowrules.nix
    ./keybinds.nix
    ./xdg.nix
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    # set the flake package
    package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;

    systemd = {
      enable = true;
      variables = [ "--all" ];
    };

    settings.exec-once = [
      "${lib.getExe config.programs.waybar.package}"
    ];
  };

  services = {
    hyprpaper.package = inputs.hyprpaper.packages.${pkgs.stdenv.hostPlatform.system}.hyprpaper;
  };
}
