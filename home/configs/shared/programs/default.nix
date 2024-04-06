args@{ pkgs, lib, ... }:
(lib.mapAttrs (_: expr: if lib.isFunction expr then expr args else expr) (
  lib.bird.importDir' ./. "default.nix"
))
// {
  ####################
  ### WEB BROWSERS ###
  ####################

  chromium = {
    programs.chromium.enable = true;
  };

  #################################
  ### COMMUNICATION & MESSAGING ###
  #################################

  zoom = {
    home.packages = [ pkgs.zoom-us ];
  };

  ######################
  ### MEDIA CREATION ###
  ######################

  ## VIDEO ##

  ## IMAGE ##

  gimp = {
    home.packages = [ pkgs.gimp ];
  };

  #########################
  ### MEDIA CONSUMPTION ###
  #########################

  #################################
  ### OFFICE & WRITING SOFTWARE ###
  #################################

  onlyoffice = {
    home.packages = [ pkgs.onlyoffice-bin ];
  };
  libreoffice = {
    home.packages = [ pkgs.libreoffice-qt ];
  };
  apostrophe = {
    home.packages = [ pkgs.apostrophe ];
  };

  ##########################
  ### TERMINAL EMULATORS ###
  ##########################

  ####################
  ### CODE EDITORS ###
  ####################

  neovim = {
    programs.neovim.enable = true;
    home.packages = [ pkgs.neovide ];
  };
  helix = {
    programs.helix.enable = true;
  };
  lapce = {
    home.packages = [ pkgs.lapce ];
  };

  #########################
  ### DEVELOPMENT TOOLS ###
  #########################

  ##########################
  ### SHELL ENVIRONMENTS ###
  ##########################

  #####################
  ### CLI UTILITIES ###
  #####################

  ###########################################
  ### SYSTEM ADMINISTRATION & DIAGNOSTICS ###
  ###########################################

  ###################
  ### VIDEO GAMES ###
  ###################

  ######################
  ### AUTHENTICATION ###
  ######################

  ####################
  ### FILE SHARING ###
  ####################

  ###################
  ### 3D PRINTING ###
  ###################

  ################
  ### HARDWARE ###
  ################
}
