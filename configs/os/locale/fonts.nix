{
  self,
  pkgs,
  system,
  ...
}:
{
  fonts = {
    enableDefaultPackages = true;
    fontconfig = {
      enable = true;
      hinting.enable = true;
      antialias = true;

      # Disable bitmap fonts to improve font rendering
      allowBitmaps = false;
      useEmbeddedBitmaps = false;
    };

    fontDir = {
      enable = true;
      decompressFonts = true;
    };

    packages = with pkgs; [
      # icon fonts
      material-design-icons
      font-awesome

      # Noto Fonts
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
      noto-fonts-emoji
      noto-fonts-color-emoji
      noto-fonts-extra

      # Adobe Fonts
      source-sans
      source-serif
      source-han-sans
      source-han-serif

      # Google Fonts
      google-fonts

      # Base fonts
      corefonts
      vistafonts
      liberation_ttf
      dejavu_fonts
      open-sans
      freefont_ttf
      gyre-fonts
      unifont
      roboto
      b612
      material-icons
      material-design-icons
      work-sans
      comic-neue
      source-sans
      inter
      lato
      lexend

      # Emoji fonts
      twemoji-color-font
      openmoji-color
      openmoji-black

      # Microsoft Fonts
      self.packages.${system}.ttf-ms-win11-auto

      # Apple Fonts
      # self.packages.${system}.apple-fonts

      # Nerdfonts
      nerd-fonts.fira-code
      nerd-fonts.jetbrains-mono
      nerd-fonts.caskaydia-cove
      nerd-fonts.monaspace

      # Japanese fonts
      # Fonts from Arch Wiki: https://wiki.archlinux.org/title/Localization/Japanese
      ipafont
      ipaexfont
      hanazono
      mplus-outline-fonts.githubRelease
      kanji-stroke-order-font
    ];
  };
}
