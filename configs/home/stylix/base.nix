{ inputs, ... }:
{
  imports = [ inputs.stylix.homeModules.stylix ];
  stylix = {
    enable = true; # enable Stylix
    autoEnable = true; # auto enable Stylix for all applications

    polarity = "dark";

    # Theme
    # View how themes look as text here:
    # tinted-theming.github.io/tinted-gallery/
    base16Scheme = inputs.stylix.inputs.tinted-schemes + "/base16/pop.yaml";

    # Wallpaper
    # image = ./background.jpg;

    # Opacity
    opacity.terminal = 0.9;
  };
}
