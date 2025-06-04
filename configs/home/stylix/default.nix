{ inputs, pkgs, ... }:
{
  imports = [
    inputs.stylix.homeModules.stylix
    ./fonts.nix
  ];

  stylix = {
    enable = true;
    autoEnable = true;

    polarity = "dark";
    base16Scheme = "${pkgs.base16-schemes}/share/themes/pop.yaml";

    opacity.terminal = 0.9;
  };
}
