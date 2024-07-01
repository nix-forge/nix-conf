args@{
  pkgs,
  lib,
  inputs,
  ...
}:
(lib.mapAttrs (_: expr: if lib.isFunction expr then expr args else expr) (
  lib.bird.importDir' ./. "default.nix"
))
// {
  ####################
  ### DESKTOP APPS ###
  ####################

  gnome-files = {
    home.packages = [ pkgs.gnome.nautilus ];
  };
  gnome-pdf = {
    home.packages = [ pkgs.evince ];
  };

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
  discord = {
    home.packages = [ pkgs.webcord ];
  };

  ######################
  ### MEDIA CREATION ###
  ######################

  ## VIDEO ##

  ## IMAGE ##

  gimp = {
    home.packages = [ pkgs.gimp ];
  };

  ## AUDIO ##

  reaper = {
    home.packages = [ pkgs.reaper ];
  };

  #########################
  ### MEDIA CONSUMPTION ###
  #########################

  foliate = {
    home.packages = [ pkgs.foliate ];
  };
  rhythmbox = {
    home.packages = [ pkgs.rhythmbox ];
  };

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
  spellcheck = {
    home.packages = [
      pkgs.hunspell
      pkgs.hunspellDicts.en_US
    ];
  };
  qgis = {
    home.packages =
      let
        geonix = inputs.geospatial-nix.packages.${pkgs.system};
      in
      [ geonix.qgis ];
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
  prism-launcher = {
    home.packages = [ pkgs.prismlauncher ];
  };

  ######################
  ### AUTHENTICATION ###
  ######################

  ####################
  ### FILE SHARING ###
  ####################
  rclone = {
    home.packages = [ pkgs.rclone ];
  };

  ###################
  ### 3D PRINTING ###
  ###################

  ################
  ### HARDWARE ###
  ################
}
