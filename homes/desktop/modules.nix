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
with (homeDir // homeDir.programs // homeDir.programs.editors);
[
  ## Base
  base.default

  ## Theming
  theming.basic.default
  theming.gtk

  ## Desktop Environment
  desktop-envs.hyprland.default
  ./hyprland

  ## Desktop Applications
  programs.rofi
  programs.waybar.default
  { home.packages = [ pkgs.nautilus ]; }
  { home.packages = [ pkgs.apostrophe ]; }
  { home.packages = [ pkgs.motrix ]; }
  programs.gparted

  ## Web Browsers
  programs.firefox.default
  { programs.chromium.enable = true; }

  ## Shell Environments
  shells.zsh.default

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
  neovim.default

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
  gaming.default
  { home.packages = [ pkgs.prismlauncher ]; }

  ## Misc
  { home.sessionVariables = lib.cust.env.wayland.all; }
  wayland.electron-flags
]
