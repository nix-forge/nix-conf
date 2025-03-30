{
  inputs,
  pkgs,
  lib,
  config,
  ...
}@args:
let
  hyprPkgs = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system};
  usingNixosHyprland = args ? nixosConfig && args.nixosConfig.programs.hyprland.enable;
  usingNixosHyprlandUWSM = usingNixosHyprland && args.nixosConfig.programs.hyprland.withUWSM;
in
{
  imports = [
    ./config.nix
    ./windowrules.nix
    ./keybinds.nix
    (import ./xdg.nix { inherit usingNixosHyprland; })
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    # set to the flake package or null if using nixos hyprland
    package = if usingNixosHyprland then null else hyprPkgs.hyprland;
    portalPackage = if usingNixosHyprland then null else hyprPkgs.xdg-desktop-portal-hyprland;

    systemd = {
      # TODO: change to check if nixos is using UWSM for hyprland not hyprland is setting UWSM (even better check both)
      enable = lib.mkForce (!usingNixosHyprlandUWSM);
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
