{
  tree,
  lib,
  inputs,
  pkgs,
  ...
}:
let
  homeDir = tree.configs.home;

  geonix = inputs.geospatial-nix.packages.${pkgs.system};
in
builtins.map (x: if x ? "default" then x.default else x) (
  with (homeDir // homeDir.programs // homeDir.programs.editors);
  [
    ## Base
    base

    ## Theming
    theming.basic
    theming.gtk

    ## Desktop Environment
    desktop-envs.hyprland
    ./hyprland

    ## Desktop Applications
    programs.rofi
    programs.waybar
    { home.packages = [ pkgs.nautilus ]; }
    { home.packages = [ pkgs.apostrophe ]; }
    { home.packages = [ pkgs.motrix ]; }
    programs.gparted

    ## Web Browsers
    programs.firefox
    { programs.chromium.enable = true; }

    ## Shell Environments
    shells.zsh

    ## Terminal Emulators
    programs.kitty

    ## Developement Tools
    dev.docs
    dev.direnv
    dev.github-cli
    dev.nix-formatter

    ## Developement Languages
    dev.languages.c

    ## Code Editors
    neovim

    vscode.settings
    vscode.keybinds
    vscode.languages.cpp
    vscode.languages.nix
    vscode.languages.web
    vscode.languages.python
    vscode.languages.bash
    vscode.languages.verilog
    vscode.languages.javascript
    vscode.languages.typescript

    ## Communication
    programs.discord
    { home.packages = [ pkgs.slack ]; }

    ## Media Consumption
    programs.spotify
    { home.packages = [ pkgs.rhythmbox ]; }

    ## Office Software
    programs.libreoffice
    { home.packages = [ pkgs.kdePackages.okular ]; }
    { home.packages = [ geonix.qgis ]; }

    ## Video Games
    gaming
    { home.packages = [ pkgs.prismlauncher ]; }

    ## Misc
    { home.sessionVariables = lib.cust.env.wayland.all; }
    wayland.electron-flags
  ]
)
