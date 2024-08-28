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
  rofi
  waybar.default
  { home.packages = [ pkgs.nautilus ]; }
  { home.packages = [ pkgs.apostrophe ]; }
  { home.packages = [ pkgs.motrix ]; }
  gparted

  ## Web Browsers
  firefox.default
  { programs.chromium.enable = true; }

  ## Shell Environments
  shells.zsh.default

  ## Terminal Emulators
  kitty

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
  discord
  { home.packages = [ pkgs.slack ]; }

  ## Media Consumption
  spotify
  { home.packages = [ pkgs.rhythmbox ]; }

  ## Office Software
  libreoffice
  { home.packages = [ pkgs.kdePackages.okular ]; }
  { home.packages = [ geonix.qgis ]; }

  ## Video Games
  gaming.default
  { home.packages = [ pkgs.prismlauncher ]; }

  ## Misc
  { home.sessionVariables = lib.cust.env.wayland.all; }
  wayland.electron-flags
]
