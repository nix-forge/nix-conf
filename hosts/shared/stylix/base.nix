{ inputs, pkgs, ... }:
{
  imports = [ inputs.stylix.nixosModules.stylix ];
  stylix.image = "${inputs.hyprland.packages.${pkgs.system}.hyprland}/share/hyprland/wall0.png";
  stylix.base16Scheme = "${pkgs.base16-schemes}/share/themes/pop.yaml";

  stylix.polarity = "dark";

  stylix.opacity.terminal = 0.9;
}
