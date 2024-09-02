{ inputs, pkgs, ... }:
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
  };

  services = {
    hyprpaper.package = inputs.hyprpaper.packages.${pkgs.stdenv.hostPlatform.system}.hyprpaper;
  };
}
