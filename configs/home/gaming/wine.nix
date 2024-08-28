{ pkgs, config, ... }:
{
  home.packages = [
    (pkgs.wineWowPackages.stagingFull.override { waylandSupport = true; })
    pkgs.winetricks
  ];

  home.sessionVariables = {
    WINEARCH = "win64";
    WINEPREFIX = "${config.xdg.dataHome}/wine";
  };
}
