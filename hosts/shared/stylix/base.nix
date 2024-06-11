{ inputs, pkgs, ... }:
{
  imports = [ inputs.stylix.nixosModules.stylix ];
  stylix.image = ./background.jpg;
  stylix.base16Scheme = "${pkgs.base16-schemes}/share/themes/pop.yaml";

  stylix.polarity = "dark";

  stylix.opacity.terminal = 0.9;
}
