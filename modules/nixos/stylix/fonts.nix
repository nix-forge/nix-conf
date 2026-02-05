{ pkgs, config, ... }:
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
      package = pkgs.noto-fonts-color-emoji;
      name = "Noto Color Emoji";
    };
  };

  fonts.fontconfig = {
    enable = true;
    useEmbeddedBitmaps = true;
    defaultFonts = {
      serif = [
        config.stylix.fonts.serif.name
        "Noto Serif CJK SC"
        "Noto Serif CJK TC"
        "Noto Serif CJK HK"
        "Noto Serif CJK JP"
        "Noto Serif CJK KR"
        "Noto Color Emoji"
      ];
      sansSerif = [
        config.stylix.fonts.sansSerif.name
        "Noto Sans CJK SC"
        "Noto Sans CJK TC"
        "Noto Sans CJK HK"
        "Noto Sans CJK JP"
        "Noto Sans CJK KR"
      ];
      monospace = [
        config.stylix.fonts.monospace.name
        "Noto Sans Mono CJK SC"
        "Noto Sans Mono CJK TC"
        "Noto Sans Mono CJK HK"
        "Noto Sans Mono CJK JP"
        "Noto Sans Mono CJK KR"
      ];
      emoji = [ config.stylix.fonts.emoji.name ];
    };
  };
}
