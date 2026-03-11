{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
  inherit (config.home) homeDirectory;
in
{
  xdg = {
    enable = true;

    configHome = "${homeDirectory}/.config";
    dataHome = "${homeDirectory}/.local/share";
    stateHome = "${homeDirectory}/.local/state";
    cacheHome = "${homeDirectory}/.cache";

    userDirs = {
      enable = true;
      createDirectories = true;
      extraConfig = {
        DEVELOPER = "${homeDirectory}/Developer";
        SCREENSHOTS = "${config.xdg.userDirs.pictures}/Screenshots";
      };
      videos = lib.mkIf isDarwin (lib.mkDefault "${homeDirectory}/Movies");
      templates = lib.mkIf isDarwin (lib.mkDefault null);
    };
  };

  home.preferXdgDirectories = config.xdg.enable;
}
