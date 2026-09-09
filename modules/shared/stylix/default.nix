let
  targetModules =
    inputs: class:
    (inputs.nix-config-framework.lib.mkSharedModuleSet {
      root = ./.;
      inherit class;
      args = { inherit inputs; };
    }).targets;
  themeDefinitions = inputs: import ./schemes.nix { inherit inputs; };
  themeNames = inputs: (themeDefinitions inputs).names;
  themeSchemes = inputs: (themeDefinitions inputs).schemes;

  fontCatalog = import ../fonts/packages.nix { };
  fontFallbacks = fontCatalog.fallbacks;

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
      lib,
      config,
      osConfig ? null,
      ...
    }:
    {
      enable = lib.mkDefault (if osConfig == null then true else osConfig.stylix.enable or true);
      autoEnable = lib.mkDefault (if osConfig == null then true else osConfig.stylix.autoEnable or true);

      # Keep Stylix and its generated targets on the selected shared palette.
      base16Scheme = (themeSchemes inputs).${config.appearance.theme};
      polarity = "dark";

      opacity.terminal = 0.9;

      fonts = fontCatalog.roles pkgs;
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
      imports = [
        inputs.stylix.nixosModules.default
        (targetModules inputs "nixos")
      ];

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
          (stylixShared {
            inherit
              config
              inputs
              pkgs
              lib
              ;
          })
          (linuxShared { inherit pkgs; })
          { homeManagerIntegration.autoImport = false; }
        ];

        appearance.palette = semanticPalette config;

        # Stylix installs the four primary faces. Keep its role names at the
        # head of each Fontconfig alias, then make multilingual and emoji
        # fallback deterministic for every user and service on the host.
        fonts.fontconfig.defaultFonts = lib.mkIf config.stylix.enable (
          lib.mkForce (fontFallbacks config.stylix.fonts)
        );
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
      imports = [
        inputs.stylix.darwinModules.default
        (targetModules inputs "darwin")
      ];

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
        (stylixShared {
          inherit
            config
            inputs
            pkgs
            lib
            ;
        })
        {
          homeManagerIntegration.autoImport = false;
          # Personal fonts, including roles, are installed natively by HM once.
          # nix-darwin owns only the shared Apple document collection.
          targets.font-packages.enable = false;
        }
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
      imports = [
        inputs.stylix.homeModules.default
        (import ./home.nix).homeManager
      ];

      options.appearance.theme = lib.mkOption {
        type = lib.types.enum (themeNames inputs);
        default =
          if osConfig != null then
            osConfig.appearance.theme or (themeDefinitions inputs).defaultName
          else
            (themeDefinitions inputs).defaultName;
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
          (stylixShared {
            inherit
              osConfig
              config
              inputs
              pkgs
              lib
              ;
          })
          { overlays.enable = lib.mkForce (!usesGlobalPkgs); }
          (lib.mkIf isLinux (linuxShared {
            inherit pkgs;
          }))
        ];

        appearance.palette = semanticPalette config;

        # Home Manager writes its own Fontconfig configuration. Mirror the
        # system policy here so user applications receive the same fallbacks.
        fonts.fontconfig.defaultFonts = lib.mkIf config.stylix.enable (
          lib.mkForce (fontFallbacks config.stylix.fonts)
        );
      };
    };
}
