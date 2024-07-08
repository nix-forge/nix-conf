{ inputs, pkgs, ... }:
{
  imports = [ inputs.stylix.nixosModules.stylix ];
  stylix = {
    enable = true; # enable Stylix
    autoEnable = true; # auto enable Stylix for all applications

    # Theme
    base16Scheme = "${pkgs.base16-schemes}/share/themes/pop.yaml";
    polarity = "dark";

    # Wallpaper
    image = ./background.jpg;

    # Opacity
    opacity.terminal = 0.9;
  };
}
