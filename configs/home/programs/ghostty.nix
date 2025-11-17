{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;
in
{
  programs.ghostty = {
    enable = true;
    package = lib.mkIf isDarwin pkgs.ghostty-bin;

    settings = {
      background-blur-radius = 20;
      mouse-hide-while-typing = true;
      window-decoration = lib.mkIf isLinux false;

      shell-integration = false; # home-manager handles this
      shell-integration-features = true;

      auto-update = false;
    }
    // lib.optionalAttrs (builtins.hasAttr "stylix" config) {
      font-size = lib.mkForce (config.stylix.fonts.sizes.terminal * 4.0 / 3.0);
    };
  };
}
