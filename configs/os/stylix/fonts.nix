{ pkgs, ... }:
{
  stylix.fonts = {
    monospace = {
      package = pkgs.nerdfonts.override { fonts = [ "Monaspace" ]; };
      name = "MonaspiceNe Nerd Font";
    };

    sansSerif = {
      package = pkgs.noto-fonts;
      name = "Noto Sans";
    };

    serif = {
      package = pkgs.noto-fonts;
      name = "Noto Serif";
    };

    emoji = {
      package = pkgs.noto-fonts-emoji;
      name = "Noto Color Emoji";
    };
  };
}
