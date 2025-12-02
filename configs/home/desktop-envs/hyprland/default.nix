{
  inputs,
  pkgs,
  lib,
  config,
  ...
}@args:
let
  hyprPkgs = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system};
  nixosHyprland = args ? nixosConfig && args.nixosConfig.programs.hyprland.enable;
  UWSMConfig = args.nixosConfig.programs.uwsm;
  UWSMHyprland =
    nixosHyprland && UWSMConfig.enable && UWSMConfig.waylandCompositors ? hyprland;
in
{
  imports = [
    ./config.nix
    ./windowrules.nix
    ./keybinds.nix
    (import ./xdg.nix { inherit nixosHyprland; })
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    # set to the flake package or null if using nixos hyprland
    package = if nixosHyprland then null else hyprPkgs.hyprland;
    portalPackage =
      if nixosHyprland then null else hyprPkgs.xdg-desktop-portal-hyprland;

    systemd = {
      enable = lib.mkForce (!UWSMHyprland);
      variables = [ "--all" ];
    };

    settings.exec-once = [
      "${lib.getExe config.programs.waybar.package}"

      "hyprctl setcursor ${config.gtk.cursorTheme.name} ${builtins.toString config.gtk.cursorTheme.size}"
    ];
  };

  # TODO: Add support for choosing the GPU for Hyprland
  # Set the environment variables for Hyprland
  xdg.configFile."uwsm/env-hyprland".text = lib.concatStringsSep "\n" [
    ''
      # Nix Environment Variables
      export NIXOS_OZONE_WL=1

      # Toolkit Backend Variables
      export GDK_BACKEND=wayland,x11,*
      export SDL_VIDEODRIVER=wayland,x11,windows
      export CLUTTER_BACKEND=wayland

      # Qt Variables
      export QT_AUTO_SCREEN_SCALE_FACTOR=1
      export QT_QPA_PLATFORM=wayland;xcb
      export QT_WAYLAND_DISABLE_WINDOWDECORATION=1

      # Electron Apps using Electron 28 or newer
      export ELECTRON_OZONE_PLATFORM_HINT=auto

      # Java Variables
      export _JAVA_AWT_WM_NONREPARENTING=1

      # Theming Related Variables
      export GTK_THEME=${config.gtk.theme.name}
      export XCURSOR_THEME=${config.gtk.cursorTheme.name}
      export XCURSOR_SIZE=${builtins.toString config.gtk.cursorTheme.size}
    ''

    (lib.optionals
      (
        config.home.sessionVariables ? IGPU_CARD
        && config.home.sessionVariables ? DGPU_CARD
      )
      ''
        # Hyprland GPU Variables
        export AQ_DRM_DEVICES=${config.home.sessionVariables.IGPU_CARD}:${config.home.sessionVariables.DGPU_CARD}
      ''
    )
  ];

  services = {
    hyprpaper.package =
      inputs.hyprpaper.packages.${pkgs.stdenv.hostPlatform.system}.hyprpaper;
  };
}
