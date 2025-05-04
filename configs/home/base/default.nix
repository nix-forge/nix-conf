{ pkgs, lib, ... }:
{
  imports = [ ./misc.nix ];

  home.stateVersion = "25.05";

  xdg.enable = true;
  fonts.fontconfig.enable = true;

  xdg.userDirs = lib.mkIf pkgs.stdenv.isLinux {
    enable = true;
    createDirectories = true;
  };
}
