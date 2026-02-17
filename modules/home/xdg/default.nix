{ config, ... }:
{
  xdg = {
    enable = true;

    configHome = "${config.home.homeDirectory}/.config";
    dataHome = "${config.home.homeDirectory}/.local/share";
    stateHome = "${config.home.homeDirectory}/.local/state";
    cacheHome = "${config.home.homeDirectory}/.cache";

    userDirs = {
      enable = true;
      createDirectories = true;
      extraConfig = {
        PROJECTS = "${config.home.homeDirectory}/Projects";
      };
    };
  };

  home.preferXdgDirectories = config.xdg.enable;
}
