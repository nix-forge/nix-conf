{
  homeManager =
    {
      config,
      lib,
      pkgs,
      inputs,
      options,
      ...
    }:
    let
      spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.hostPlatform.system};
      cfg = config.stylix.targets.spicetify;
      palette = config.appearance.palette;
      isCarbonNeon = builtins.elem config.appearance.theme [
        "carbon-neon"
        "carbon-neon-oled"
      ];
      carbonNeonScheme = {
        inherit (palette) text;
        subtext = palette.muted;
        sidebar-text = palette.text;
        main = palette.surface;
        main-elevated = palette.surfaceRaised;
        highlight = palette.surfaceRaised;
        highlight-elevated = palette.surfaceHover;
        sidebar = palette.surface;
        player = palette.surface;
        card = palette.surfaceHover;
        shadow = "000000";
        selected-row = palette.muted;
        button = palette.accent;
        # Keep primary actions and selected playback states in Carbon's cyan rather
        # than Spotify's familiar green.  The latter is too close to Carbon's
        # reserved success colour and was the lime control shown in the screenshot.
        button-active = palette.accent;
        button-disabled = palette.outline;
        tab-active = palette.surfaceRaised;
        notification = palette.accent;
        notification-error = palette.danger;
        misc = palette.muted;
      };
      # `additionalCss` is an in-memory Home Manager value. Substituting its one
      # value during evaluation avoids trying to build a Linux derivation merely
      # to read CSS on the macOS deployment workstation.
      carbonNeonCss =
        let
          template = builtins.readFile ./carbon-neon.css;
          templateTokens = [
            "NIX_STYLIX_SANS_SERIF"
            "NIX_PALETTE_WARNING"
            "NIX_PALETTE_ACCENT_HOVER"
            "NIX_PALETTE_ACCENT_PRESSED"
          ];
          rendered = builtins.replaceStrings templateTokens [
            (builtins.toJSON config.stylix.fonts.sansSerif.name)
            "#${palette.warning}"
            "#${palette.accentHover}"
            "#${palette.accentPressed}"
          ] template;
        in
        assert lib.all (token: lib.hasInfix token template) templateTokens;
        assert lib.all (token: !(lib.hasInfix token rendered)) templateTokens;
        rendered;
      carbonNeonTheme = spicePkgs.themes.default // {
        name = "CarbonNeon";
        additionalCss = carbonNeonCss;
      };
      theme =
        if config.appearance.theme == "catppuccin-mocha" then
          {
            theme = spicePkgs.themes.catppuccin;
            colorScheme = "mocha";
          }
        else if config.appearance.theme == "gruvbox-dark-medium" then
          {
            # Spicetify's upstream Text theme includes the canonical Gruvbox
            # Medium palette, including its #282828 background.
            theme = spicePkgs.themes.text;
            colorScheme = "Gruvbox";
          }
        else
          {
            # The base theme supplies Spicetify's layout hooks.  The local CSS also
            # maps Spotify's newer native tokens to the generated Carbon palette.
            theme = carbonNeonTheme;
            colorScheme = "custom";
          };
    in
    {
      key = "nix-conf/stylix/spicetify/homeManager";
      _file = __curPos.file;
      options.stylix.targets.spicetify.custom.enable = lib.mkEnableOption "the native Spotify theme" // {
        default = true;
      };
      config = lib.optionalAttrs (options.programs ? spicetify) (
        lib.mkIf (config.stylix.enable && cfg.enable && cfg.custom.enable) {
          # The native port replaces upstream's generated color.ini.
          stylix.targets.spicetify.colors.enable = lib.mkDefault false;
          programs.spicetify = {
            # Use the maintained native port for the selected shared palette.
            theme = lib.mkIf config.programs.spicetify.enable (lib.mkDefault theme.theme);
            colorScheme = lib.mkIf config.programs.spicetify.enable (lib.mkDefault theme.colorScheme);
            customColorScheme = lib.mkIf (config.programs.spicetify.enable && isCarbonNeon) carbonNeonScheme;

          };
        }
      );
    };
}
