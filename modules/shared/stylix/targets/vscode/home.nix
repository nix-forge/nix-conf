{
  homeManager =
    {
      config,
      lib,
      pkgs,
      inputs,
      ...
    }:
    let
      extensions = (pkgs.extend inputs.nix4vscode.overlays.default).nix4vscode;
      palette = config.appearance.palette;
      cfg = config.stylix.targets.vscode;
      carbonNeonThemeSource = pkgs.linkFarm "carbon-neon-vscode-theme-source" {
        "package.json" = ./carbon-neon/package.json;
        "themes/carbon-neon-color-theme.json" =
          (pkgs.formats.json { }).generate "carbon-neon-color-theme.json"
            ((import ./carbon-neon/themes/carbon-neon-color-theme.nix).render { inherit palette; });
        "themes/carbon-neon-oled-color-theme.json" =
          (pkgs.formats.json { }).generate "carbon-neon-oled-color-theme.json"
            ((import ./carbon-neon/themes/carbon-neon-oled-color-theme.nix).render { inherit palette; });
      };
      carbonNeonTheme = pkgs.vscode-utils.buildVscodeExtension {
        pname = "carbon-neon-theme";
        version = "0.1.0";
        src = carbonNeonThemeSource;
        sourceRoot = "carbon-neon-vscode-theme-source";
        vscodeExtPublisher = "ianhollow";
        vscodeExtName = "carbon-neon-theme";
        vscodeExtUniqueId = "ianhollow.carbon-neon-theme";
      };
      theme =
        if config.appearance.theme == "catppuccin-mocha" then
          {
            extensionIds = [
              "catppuccin.catppuccin-vsc"
              "catppuccin.catppuccin-vsc-icons"
              "pkief.material-product-icons"
            ];
            colorTheme = "Catppuccin Mocha";
            iconTheme = "catppuccin-mocha";
            productIconTheme = "material-product-icons";
            localExtensions = [ ];
          }
        else if config.appearance.theme == "gruvbox-dark-medium" then
          {
            extensionIds = [
              "tomphilbin.gruvbox-themes"
              "pkief.material-icon-theme"
              "pkief.material-product-icons"
            ];
            colorTheme = "Gruvbox Dark (Medium)";
            iconTheme = "material-icon-theme";
            productIconTheme = "material-product-icons";
            localExtensions = [ ];
          }
        else
          {
            extensionIds = [
              "pkief.material-icon-theme"
              "pkief.material-product-icons"
            ];
            colorTheme =
              if config.appearance.theme == "carbon-neon-oled" then "Carbon Neon OLED" else "Carbon Neon";
            iconTheme = "material-icon-theme";
            productIconTheme = "material-product-icons";
            localExtensions = [ carbonNeonTheme ];
          };
    in
    {
      key = "nix-conf/stylix/vscode/homeManager";
      _file = __curPos.file;
      options.stylix.targets.vscode.custom.enable = lib.mkEnableOption "the native VS Code theme" // {
        default = true;
      };
      config =
        lib.mkIf (config.stylix.enable && cfg.enable && cfg.custom.enable && config.programs.vscode.enable)
          {
            # Keep upstream fonts, but omit its unused generated theme extension.
            stylix.targets.vscode.colors.enable = lib.mkDefault false;
            # This fallback is an application dependency, even with no design collection.
            home.packages = lib.optionals (
              cfg.fonts.enable && cfg.profileNames != [ ] && config.typography.designLibrary == "none"
            ) [ (pkgs.google-fonts.override { fonts = [ "Iosevka Charon Mono" ]; }) ];

            programs.vscode.profiles = lib.genAttrs cfg.profileNames (_: {
              extensions = theme.localExtensions ++ extensions.forVscode theme.extensionIds;
              userSettings = {
                ## Appearances ##
                "editor.cursorSmoothCaretAnimation" = "explicit";
                "editor.cursorStyle" = "block";
                "editor.cursorBlinking" = "smooth";
                # CodeLens inherits these features while using a different font.
                # Stylistic sets are font-specific: Inter's ss05/ss06 enclose
                # ordinary characters in circles/squares. Use standard ligatures.
                "editor.fontLigatures" = true;
                "terminal.integrated.fontLigatures.enabled" = true;
                # Iosevka's text stopwatch fits a terminal cell. Chromium otherwise
                # falls back to a wide color glyph that xterm squeezes horizontally.
                # Keep emoji presentation and overlapping-glyph protection intact.
                # Iosevka Charon Mono is included in our shared Google Fonts package.
                "terminal.integrated.fontFamily" =
                  lib.mkIf cfg.fonts.enable "'${config.stylix.fonts.monospace.name}', 'Iosevka Charon Mono'";
                "editor.fontVariations" = true;

                # Upstream's font block also selects "Stylix". Override only that key.
                # Keep VS Code's native theme and icon port aligned with Stylix.
                "workbench.colorTheme" = lib.mkForce theme.colorTheme;
                "workbench.iconTheme" = theme.iconTheme;
                "workbench.productIconTheme" = lib.mkIf (theme.productIconTheme != null) theme.productIconTheme;

                "terminal.integrated.minimumContrastRatio" = lib.mkDefault 1;
              };
            });
          };
    };
}
