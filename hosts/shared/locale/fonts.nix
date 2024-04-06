{ pkgs, ... }:
{
  fonts = {
    # use fonts specified by user rather than default ones
    enableDefaultPackages = true;
    fontDir.enable = true;

    # TODO: add more fonts related to languages enabled in the system

    packages = with pkgs; [
      # icon fonts
      material-design-icons
      font-awesome

      # Noto Fonts
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
      noto-fonts-emoji
      noto-fonts-extra

      # Adobe Fonts
      source-sans
      source-serif
      source-han-sans
      source-han-serif

      # Google Fonts
      google-fonts

      # Nerdfonts
      (nerdfonts.override {
        fonts = [
          "FiraCode"
          "JetBrainsMono"
          "CascadiaCode"
        ];
      })

      # Japanese fonts
      # Fonts from Arch Wiki: https://wiki.archlinux.org/title/Localization/Japanese
      ipafont
      ipaexfont
      hanazono
      mplus-outline-fonts.githubRelease
      kanji-stroke-order-font
    ];

    fontconfig.defaultFonts = {
      serif = [
        "Noto Serif"
        "Source Han Serif"
      ];
      sansSerif = [
        "Noto Sans"
        "Source Han Sans"
      ];
      monospace = [
        "JetBrainsMono Nerd Font"
        "Noto Sans Mono"
      ];
      emoji = [ "Noto Color Emoji" ];
    };
  };
}
