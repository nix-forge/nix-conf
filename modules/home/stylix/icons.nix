{ pkgs, ... }:
{
  stylix.icons = {
    enable = pkgs.stdenv.hostPlatform.isLinux;
    package = pkgs.papirus-icon-theme;
    dark = "Papirus-Dark";
    light = "Papirus";
  };
}
