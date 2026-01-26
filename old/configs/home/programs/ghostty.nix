{ lib, pkgs, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;
in
{
  programs.ghostty = {
    enable = true;
    package = lib.mkIf isDarwin pkgs.ghostty-bin;

    # DOCS: https://ghostty.org/docs/config/reference
    settings = {
      background-blur-radius = 20;
      mouse-hide-while-typing = true;
      window-decoration = lib.mkIf isLinux false;

      shell-integration = "none"; # home-manager handles this
      shell-integration-features = true;

      auto-update = "off";
    };
  };
}
