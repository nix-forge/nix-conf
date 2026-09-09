{
  pkgs,
  config,
  lib,
  ...
}:
let
  catalog = import ../../shared/fonts/packages.nix { };
in
{
  stylix.fonts = lib.mkDefault (catalog.roles pkgs);
  fonts.fontconfig = {
    enable = true;
    defaultFonts = lib.mkDefault (catalog.fallbacks config.stylix.fonts);
  };
}
