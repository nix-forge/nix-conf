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
    # ./xdg.nix
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    # set the flake package
    package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
    portalPackage =
      inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;

    systemd = {
      enable = true;
      variables = [ "--all" ];
    };

    settings.exec-once = [
      "${lib.getExe config.programs.waybar.package}"

      "hyprctl setcursor ${config.gtk.cursorTheme.name} ${builtins.toString (config.gtk.cursorTheme.size)}"
    ];
  };

  services = {
    hyprpaper.package = inputs.hyprpaper.packages.${pkgs.stdenv.hostPlatform.system}.hyprpaper;
  };
}
