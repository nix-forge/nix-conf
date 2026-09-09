# Catalog only: package construction and repairs belong to nixpkgs-personal.
_:
let
  catalog = {
    roles = pkgs: {
      monospace = {
        package = pkgs.nerd-fonts.monaspace;
        name = "MonaspiceNe Nerd Font";
      };
      sansSerif = {
        package = pkgs.inter;
        name = "Inter";
      };
      serif = {
        package = pkgs.literata;
        name = "Literata";
      };
      emoji = {
        package = pkgs.noto-fonts-color-emoji;
        name = "Noto Color Emoji";
      };
    };
    fallbacks = fonts: {
      serif = [
        fonts.serif.name
        "Noto Serif CJK SC"
        "Noto Serif CJK TC"
        "Noto Serif CJK HK"
        "Noto Serif CJK JP"
        "Noto Serif CJK KR"
        "Noto Color Emoji"
      ];
      sansSerif = [
        fonts.sansSerif.name
        "Noto Sans CJK SC"
        "Noto Sans CJK TC"
        "Noto Sans CJK HK"
        "Noto Sans CJK JP"
        "Noto Sans CJK KR"
        "Noto Color Emoji"
      ];
      monospace = [
        fonts.monospace.name
        "Noto Sans Mono CJK SC"
        "Noto Sans Mono CJK TC"
        "Noto Sans Mono CJK HK"
        "Noto Sans Mono CJK JP"
        "Noto Sans Mono CJK KR"
        "Noto Color Emoji"
      ];
      emoji = [ fonts.emoji.name ];
    };

    appleDocumentFonts =
      packages: with packages.apple-fonts.assets; [
        apple-asset-brill-italic
        apple-asset-brill-roman
        apple-asset-canela-regular
        apple-asset-caneladeck-regular
        apple-asset-canelatext-regular
        apple-asset-domainedisplay-regular
        apple-asset-foundersgrotesk-regular
        apple-asset-foundersgroteskcond-reg
        apple-asset-foundersgrotesktext-regular
        apple-asset-graphik-regular
        apple-asset-graphikcompact-regular
        apple-asset-produkt-regular
        apple-asset-proximanova-regular
        apple-asset-publicoheadline-roman
        apple-asset-publicotext-roman
        apple-asset-spotmono-regular
      ];

    base =
      pkgs: personal: with pkgs; [
        material-design-icons
        font-awesome
        material-icons
        noto-fonts
        noto-fonts-cjk-sans
        noto-fonts-cjk-serif
        noto-fonts-lgc-plus
        source-sans
        source-serif
        source-han-sans
        source-han-serif
        corefonts
        liberation_ttf
        dejavu_fonts
        open-sans
        freefont_ttf
        gyre-fonts
        unifont
        roboto
        b612
        work-sans
        inter
        lato
        lexend
        literata
        noto-fonts-color-emoji
        personal.twemoji-color-font-optional
        twitter-color-emoji
        openmoji-color
        (joypixels.override { acceptLicense = true; })
        personal.ttf-ms-win11-auto
        nerd-fonts.fira-code
        nerd-fonts.jetbrains-mono
        nerd-fonts.caskaydia-cove
        nerd-fonts.monaspace
        ipafont
        ipaexfont
        hanazono
        kanji-stroke-order-font
        xits-math
        newcomputermodern
        cm_unicode
      ];
    design =
      pkgs: personal: choice:
      if choice == "full" then
        [
          personal.google-fonts-design
          personal.mplus-outline-fonts-compatible
        ]
      else if choice == "curated" then
        [
          pkgs.mplus-outline-fonts.githubRelease
          # A small collection for hosts that do not need the complete catalog.
          (pkgs.google-fonts.override { fonts = [ "Iosevka Charon Mono" ]; })
        ]
      else
        [ pkgs.mplus-outline-fonts.githubRelease ];
    optionalEmoji =
      pkgs: personal:
      [
        personal.firefox-emoji
        personal.emojione-legacy
        personal.mutant-standard-emoji
      ]
      ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [ personal.apple-color-emoji ];
    select =
      pkgs: personal: typography:
      pkgs.lib.unique (
        catalog.base pkgs personal
        ++ catalog.design pkgs personal typography.designLibrary
        ++ pkgs.lib.optionals typography.optionalEmoji.enable (catalog.optionalEmoji pkgs personal)
      );
  };
in
catalog
