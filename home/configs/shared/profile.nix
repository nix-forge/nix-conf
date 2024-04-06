args@{
  self,
  config,
  lib,
  inputs,
  pkgs,
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
      development = shared.development;
    in
    [
      ###############################
      ### MODULES & MISCELLANEOUS ###
      ###############################

      ### DEFAULT PROGRAMS ###

      ##############################
      ### USER-SPECIFIC PROGRAMS ###
      ##############################

      ### WEB BROWSERS ###
      programs.firefox

      ### COMMUNICATION & MESSAGING ###

      ### MEDIA CREATION ###

      ### MEDIA CONSUMPTION ###
      programs.spotify

      ### OFFICE & WRITING SOFTWARE ###
      programs.zoom

      ### TERMINAL EMULATORS ###
      programs.kitty

      ### CODE EDITORS ###
      programs.vscode.settings
      programs.vscode.languages.cpp
      programs.vscode.languages.bash
      programs.vscode.languages.nix
      programs.vscode.languages.web
      programs.vscode.languages.python

      ### DEVELOPMENT TOOLS ###
      development.tools.docs
      development.tools.direnv

      ## DEVELOPMENT ##
      development.languages.c

      ### SHELL ENVIRONMENTS ###
      programs.zsh

      ### CLI UTILITIES ###

      ### SYSTEM ADMINISTRATION & DIAGNOSTICS ###

      ### VIDEO GAMES ###

      ### AUTHENTICATION ###

      ### FILE SHARING ###

      ### 3D PRINTING ###

      ### HARDWARE ###

      ##############################
      ### USER-SPECIFIC SERVICES ###
      ##############################

      ### BACKGROUND SYNC & NOTIFICATIONS ###

      ### MEDIA ###

      ### FILE SYNCHRONIZATION ###

      ### DEVICE MANAGEMENT ###

      ### SECRET MANAGEMENT ###
    ];
}
