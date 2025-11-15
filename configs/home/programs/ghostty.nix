{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
in
{
  programs.ghostty = {
    enable = true;
    package = lib.mkIf isDarwin pkgs.ghostty-bin;

    settings = {
      background-blur-radius = 20;
      mouse-hide-while-typing = true;
      window-decoration = isDarwin;
    }
    // lib.optionalAttrs (builtins.hasAttr "stylix" config) {
      font-size = lib.mkForce (config.stylix.fonts.sizes.terminal * 4.0 / 3.0);
    };
  };
}
