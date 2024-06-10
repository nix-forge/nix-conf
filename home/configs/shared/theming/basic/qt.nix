{ pkgs, ... }:
{
  qt = {
    enable = true;
    platformTheme.name = "qtct";
    style = {
      package = pkgs.kdePackages.breeze;
      name = "breeze";
    };
  };
}
