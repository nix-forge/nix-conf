args@{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
{
  ################
  ### PREAMBLE ###
  ################

  # fix for some display managers not using ~/.profile
  systemd.user.sessionVariables = config.home.sessionVariables;

  ####################################
  ### BASIC USER ENVIRONMENT SETUP ###
  ####################################
  xdg.enable = true;
  xdg.userDirs.enable = true;
  xdg.userDirs.createDirectories = true;

  programs.home-manager.enable = true;

  # should already be enabled at system level
  # fontconfig required to make user-fonts by name
  # TODO: figure out how to make ~/.local/share/fonts
  fonts.fontconfig.enable = true;

  home.sessionVariables = {
    BROWSER = "firefox";
    TERMINAL = "kitty";
    EDITOR = "nvim";
  };

  ##########################
  ### PACKAGES & MODULES ###
  ##########################
  imports =
    let
      shared = lib.bird.importDir' ./. "profile.nix";
      programs = shared.programs args;
      wayland = shared.wayland;
    in
    [
      ###############################
      ### MODULES & MISCELLANEOUS ###
      ###############################
      wayland.electron-flags

      ### DEFAULT PROGRAMS ###
      programs.gnome-files
      programs.gnome-pdf
      programs.okular
      programs.motrix

      ##############################
      ### USER-SPECIFIC PROGRAMS ###
      ##############################

      ### WEB BROWSERS ###
      programs.firefox
      programs.chromium

      ### COMMUNICATION & MESSAGING ###
      # programs.zoom
      programs.discord
      # programs.slack

      ### MEDIA CREATION ###
      programs.reaper

      ### MEDIA CONSUMPTION ###
      programs.spotify
      programs.rhythmbox
      # programs.foliate

      ### OFFICE & WRITING SOFTWARE ###
      programs.libreoffice
      programs.spellcheck
      programs.qgis

      ### TERMINAL EMULATORS ###
      programs.kitty

      ### CODE EDITORS ###
      programs.editors.neovim

      programs.vscode.settings
      programs.vscode.keybinds
      programs.vscode.languages.cpp
      programs.vscode.languages.nix
      programs.vscode.languages.web
      programs.vscode.languages.python
      programs.vscode.languages.bash
      programs.vscode.languages.verilog
      programs.vscode.languages.javascript
      programs.vscode.languages.typescript

      ### DEVELOPMENT TOOLS ###
      programs.dev.tools.docs
      programs.dev.tools.direnv
      programs.dev.tools.nix-formatter
      programs.dev.tools.github-cli

      ## DEVELOPMENT ##
      programs.dev.languages.c

      ### SHELL ENVIRONMENTS ###
      programs.zsh

      ### CLI UTILITIES ###

      ### SYSTEM ADMINISTRATION & DIAGNOSTICS ###

      ### VIDEO GAMES ###
      programs.gaming
      programs.prism-launcher

      ### AUTHENTICATION ###

      ### FILE SHARING ###
      programs.rclone

      ### 3D PRINTING ###

      ### HARDWARE ###

      ##############################
      ### USER-SPECIFIC SERVICES ###
      ##############################

      ### BACKGROUND SYNC & NOTIFICATIONS ###

      ### MEDIA ###

      ### FILE SYNCHRONIZATION ###

      ### DEVICE MANAGEMENT ###
      programs.gparted

      ### SECRET MANAGEMENT ###
    ];
}
