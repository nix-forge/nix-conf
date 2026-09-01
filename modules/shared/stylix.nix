let
  themeNames = [
    "catppuccin-mocha"
    "gruvbox-dark-medium"
    "carbon-neon"
    "carbon-neon-oled"
  ];

  themeSchemes = inputs: {
    catppuccin-mocha = inputs.stylix.inputs.tinted-schemes + "/base16/catppuccin-mocha.yaml";
    gruvbox-dark-medium = inputs.stylix.inputs.tinted-schemes + "/base16/gruvbox-dark-medium.yaml";
    carbon-neon = ../../themes/carbon-neon.yaml;
    carbon-neon-oled = ../../themes/carbon-neon-oled.yaml;
  };

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
        type = lib.types.enum themeNames;
        default = "carbon-neon";
        description = ''
          Shared dark theme for Stylix and the native application integrations.
          Available values are "catppuccin-mocha", "gruvbox-dark-medium",
          "carbon-neon", and "carbon-neon-oled".
        '';
      };

      config = {
        stylix = lib.mkMerge [
          (stylixShared { inherit config inputs pkgs; })
          (linuxShared { inherit pkgs; })
          { homeManagerIntegration.autoImport = false; }
        ];

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
        type = lib.types.enum themeNames;
        default = "carbon-neon";
        description = ''
          Shared dark theme for Stylix and the native application integrations.
          Available values are "catppuccin-mocha", "gruvbox-dark-medium",
          "carbon-neon", and "carbon-neon-oled".
        '';
      };

      config.stylix = lib.mkMerge [
        (stylixShared { inherit config inputs pkgs; })
        { homeManagerIntegration.autoImport = false; }
      ];
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
        type = lib.types.enum themeNames;
        default = if osConfig != null then osConfig.appearance.theme else "carbon-neon";
        defaultText = lib.literalExpression "osConfig.appearance.theme or \"carbon-neon\"";
        description = ''
          Shared dark theme for Stylix and native application integrations.
          Attached Home Manager profiles inherit the host selection.
        '';
      };

      config = {
        stylix = lib.mkMerge [
          (stylixShared { inherit config inputs pkgs; })
          { overlays.enable = lib.mkForce (!usesGlobalPkgs); }
          (lib.mkIf isLinux (linuxShared {
            inherit pkgs;
          }))
        ];

        # Home Manager writes its own Fontconfig configuration. Mirror the
        # system policy here so user applications receive the same fallbacks.
        fonts.fontconfig.defaultFonts = lib.mkForce (fontFallbacks config.stylix.fonts);
      };
    };
}
