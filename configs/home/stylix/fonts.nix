{ pkgs, ... }:
{
  stylix.fonts = {
    monospace = {
      package = pkgs.nerd-fonts.monaspace;
      name = "MonaspiceNe Nerd Font";
    };

    sansSerif = {
      package = pkgs.inter;
      name = "Inter";
    };

    serif = {
      package = pkgs.google-fonts;
      name = "Literata";
    };

    emoji = {
      package = pkgs.noto-fonts-emoji;
      name = "Noto Color Emoji";
    };
  };
}
