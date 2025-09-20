{ inputs, ... }:
{
  imports = [
    inputs.stylix.homeModules.stylix
    ./fonts.nix
  ];

  stylix = {
    enable = true;
    autoEnable = true;
    overlays.enable = false;

    polarity = "dark";
    base16Scheme = inputs.stylix.inputs.tinted-schemes + "/base16/pop.yaml";

    opacity.terminal = 0.9;
  };
}
