{
  homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      supportsDesktop = lib.meta.availableOn pkgs.stdenv.hostPlatform pkgs.chatgpt-latest;
      appearanceSettings = {
        desktop = {
          appearanceTheme = "dark";
          appearanceLightCodeThemeId = "codex";
          appearanceDarkCodeThemeId = "codex";
          # Keep +/- markers as a second cue alongside the diff colors.
          appearanceDiffMarkerStyle = "symbols";
          sansFontSize = 16;
          codeFontSize = 16;
          useFontSmoothing = true;
          usePointerCursors = true;
          appearanceDarkChromeTheme = {
            surface = "#${config.appearance.palette.surface}";
            ink = "#${config.appearance.palette.text}";
            accent = "#${config.appearance.palette.accent}";
            accentSource = "custom";
            # 60 leaves enabled labels below 4.5:1 with Carbon's muted ink.
            # 85 also clears that target on elevated Carbon and OLED backgrounds.
            contrast = 85;
            opaqueWindows = true;
            fonts = {
              ui = config.stylix.fonts.sansSerif.name;
              code = config.stylix.fonts.monospace.name;
            };
            semanticColors = {
              diffAdded = "#${config.appearance.palette.diffAdded}";
              diffRemoved = "#${config.appearance.palette.diffRemoved}";
              skill = "#${config.appearance.palette.special}";
            };
          };
        };
      };
    in
    {
      key = "nix-conf/stylix/codex-desktop/homeManager";
      _file = __curPos.file;
      imports = [
        (import ../../profile.nix).homeManager
        ../../../../home/dev/agentic-gui/codex/settings.nix
      ];
      options.stylix.targets.codex-desktop.enable = config.lib.stylix.mkEnableTarget "Codex Desktop" true;
      config = lib.mkIf (
        config.stylix.enable
        && config.stylix.targets.codex-desktop.enable
        && config.programs.codex.enable
        && supportsDesktop
      ) { programs.chatgpt.settings = appearanceSettings; };
    };
}
