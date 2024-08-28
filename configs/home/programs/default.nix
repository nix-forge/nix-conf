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
    home.packages = [ pkgs.nautilus ];
  };
  gnome-pdf = {
    home.packages = [ pkgs.evince ];
  };
  okular = {
    home.packages = [ pkgs.kdePackages.okular ];
  };
  motrix = {
    home.packages = [ pkgs.motrix ];
  };
  gparted = {
    home.packages = [
      pkgs.gparted
      pkgs.exfatprogs
    ];
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
    home.packages = [ pkgs.webcord-vencord ];
    # For Discord RPC
    # services.arrpc.enable = true;
  };
  slack = {
    home.packages = [ pkgs.slack ];
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

  apostrophe = {
    home.packages = [ pkgs.apostrophe ];
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
