let
  themeDefinitions = inputs: import ../../themes { inherit inputs; };
  themeNames = inputs: (themeDefinitions inputs).names;
  themeSchemes = inputs: (themeDefinitions inputs).schemes;

  fontFallbacks = fonts: {
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

  # Applications often need roles that Base16 does not name directly. Keep
  # those roles in one place, so native integrations do not each grow their
  # own slightly different interpretation of the selected scheme.
  semanticPalette =
    config:
    let
      inherit (config.lib.stylix.colors)
        base00
        base01
        base02
        base03
        base04
        base05
        base06
        base07
        base08
        base09
        base0A
        base0B
        base0C
        base0D
        base0E
        base0F
        ;
      isCarbonNeon = builtins.elem config.appearance.theme [
        "carbon-neon"
        "carbon-neon-oled"
      ];
    in
    {
      surface = base00;
      surfaceRaised = base01;
      surfaceHover = base02;
      surfaceChrome = if isCarbonNeon then "0C0D0E" else base01;
      outline = base03;
      outlineSubtle = if isCarbonNeon then "242526" else base03;
      muted = base04;
      text = base05;
      textStrong = base07;
      danger = base08;
      warning = base0A;
      success = base0B;
      info = base0C;
      accent = base0D;
      accentHover = if isCarbonNeon then "9DE0DA" else base0D;
      accentPressed = base0C;
      special = base0E;
      cursor = if isCarbonNeon then "FFCC00" else base0A;
      lineNumber = if isCarbonNeon then "56575D" else base03;
      scrollbar = if isCarbonNeon then "5E6066" else base04;
      syntaxFunction = if isCarbonNeon then "6A90D0" else base0D;

      # Carbon Neon uses a less olive, less cyan diff pair than its terminal
      # success and error swatches. Other schemes retain their native roles.
      diffAdded = if isCarbonNeon then "78C86F" else base0B;
      diffRemoved = if isCarbonNeon then "D98086" else base08;

      inherit
        base00
        base01
        base02
        base03
        base04
        base05
        base06
        base07
        base08
        base09
        base0A
        base0B
        base0C
        base0D
        base0E
        base0F
        ;
    };

  stylixShared =
    {
      inputs,
      pkgs,
      config,
      ...
    }:
    {
      enable = true;
      autoEnable = true;

      # Keep Stylix and its generated targets on the selected shared palette.
      base16Scheme = (themeSchemes inputs).${config.appearance.theme};
      polarity = "dark";

      opacity.terminal = 0.9;

      fonts = {
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
    };
  linuxShared = { pkgs, ... }: {
    cursor = {
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Classic";
      size = 20;
    };
    icons = {
      enable = true;
      package = pkgs.papirus-icon-theme;
      dark = "Papirus-Dark";
      light = "Papirus";
    };
  };
in
{
  nixos =
    {
      inputs,
      pkgs,
      lib,
      config,
      ...
    }:
    {
      imports = [ inputs.stylix.nixosModules.default ];

      options.appearance.theme = lib.mkOption {
        type = lib.types.enum (themeNames inputs);
        default = (themeDefinitions inputs).defaultName;
        description = ''
          Shared dark theme for Stylix and the native application integrations.
          Available values are "catppuccin-mocha", "gruvbox-dark-medium",
          "carbon-neon", and "carbon-neon-oled".
        '';
      };

      options.appearance.palette = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        readOnly = true;
        description = "Semantic application colors derived from the selected Stylix scheme.";
      };

      config = {
        stylix = lib.mkMerge [
          (stylixShared { inherit config inputs pkgs; })
          (linuxShared { inherit pkgs; })
          { homeManagerIntegration.autoImport = false; }
        ];

        appearance.palette = semanticPalette config;

        # Stylix installs the four primary faces. Keep its role names at the
        # head of each Fontconfig alias, then make multilingual and emoji
        # fallback deterministic for every user and service on the host.
        fonts.fontconfig.defaultFonts = lib.mkForce (fontFallbacks config.stylix.fonts);
      };
    };
  darwin =
    {
      inputs,
      pkgs,
      lib,
      config,
      ...
    }:
    {
      imports = [ inputs.stylix.darwinModules.default ];

      options.appearance.theme = lib.mkOption {
        type = lib.types.enum (themeNames inputs);
        default = (themeDefinitions inputs).defaultName;
        description = ''
          Shared dark theme for Stylix and the native application integrations.
          Available values are "catppuccin-mocha", "gruvbox-dark-medium",
          "carbon-neon", and "carbon-neon-oled".
        '';
      };

      options.appearance.palette = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        readOnly = true;
        description = "Semantic application colors derived from the selected Stylix scheme.";
      };

      config.stylix = lib.mkMerge [
        (stylixShared { inherit config inputs pkgs; })
        { homeManagerIntegration.autoImport = false; }
      ];

      config.appearance.palette = semanticPalette config;
    };
  homeManager =
    {
      inputs,
      pkgs,
      lib,
      config,
      osConfig ? null,
      ...
    }:
    let
      inherit (pkgs.stdenv.hostPlatform) isLinux;
      usesGlobalPkgs = osConfig != null && (osConfig.home-manager.useGlobalPkgs or false);
    in
    {
      imports = [ inputs.stylix.homeModules.default ];

      options.appearance.theme = lib.mkOption {
        type = lib.types.enum (themeNames inputs);
        default =
          if osConfig != null then osConfig.appearance.theme else (themeDefinitions inputs).defaultName;
        defaultText = lib.literalExpression "osConfig.appearance.theme or themeDefinitions.defaultName";
        description = ''
          Shared dark theme for Stylix and native application integrations.
          Attached Home Manager profiles inherit the host selection.
        '';
      };

      options.appearance.palette = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        readOnly = true;
        description = "Semantic application colors derived from the selected Stylix scheme.";
      };

      config = {
        stylix = lib.mkMerge [
          (stylixShared { inherit config inputs pkgs; })
          { overlays.enable = lib.mkForce (!usesGlobalPkgs); }
          (lib.mkIf isLinux (linuxShared {
            inherit pkgs;
          }))
        ];

        appearance.palette = semanticPalette config;

        # Home Manager writes its own Fontconfig configuration. Mirror the
        # system policy here so user applications receive the same fallbacks.
        fonts.fontconfig.defaultFonts = lib.mkForce (fontFallbacks config.stylix.fonts);
      };
    };
}
