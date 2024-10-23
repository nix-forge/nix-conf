{
  tree,
  pkgs,
  inputs,
  ...
}:
let
  homeDir = tree.configs.home;
  sharedDir = tree.configs.shared;
  install = pkg: { home.packages = [ pkg ]; };
in
with (homeDir // homeDir.programs // homeDir.programs.editors);
[
  ## Base
  base
  ./hardware

  ## Theming
  theming.basic
  theming.gtk

  ## Desktop Environment
  desktop-envs.hyprland
  ./hyprland

  ## Desktop Applications
  programs.rofi
  programs.waybar
  (install pkgs.nautilus)
  (install pkgs.apostrophe)
  (install pkgs.motrix)
  (install pkgs.pinta)
  (install pkgs.vlc)

  ## Utility
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
  # neovim

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
  vscode.languages.docker

  ## Communication
  programs.discord
  (install pkgs.slack)

  ## Media Consumption
  programs.spotify
  (install pkgs.rhythmbox)

  ## Office Software
  programs.libreoffice
  (install pkgs.obsidian)
  (install pkgs.kdePackages.okular)
  (install inputs.geospatial-nix.packages.${pkgs.system}.qgis)

  ## Video Games
  gaming
  (install pkgs.prismlauncher)
  (install pkgs.lutris)

  ## Misc
  { home.sessionVariables = sharedDir.env.wayland.default; }
  wayland.electron-flags
]
