{
  lib,
  myLib,
  pkgs,
  self,
  system,
  config,
  ...
}:
let
  writeBashTemplate = myLib.writers.writeBashTemplate { inherit pkgs; };
  supportsRemindctl = self.packages.${system} ? remindctl;
  supportsDesktop = self.packages.${system} ? openai-codex-desktop;
  remindctl = self.packages.${system}.remindctl;
  mattpocockSkills = self.packages.${system}.mattpocock-skills;
  pstackSkills = self.packages.${system}.pstack-skills;
  skillPath = package: name: "${package}/share/agent-skills/${name}";
  skillSet = package: names: lib.genAttrs names (name: skillPath package name);

  mattpocockCodexSkills = [
    "mattpocock-ask-matt"
    "mattpocock-codebase-design"
    "mattpocock-code-review"
    "mattpocock-diagnosing-bugs"
    "mattpocock-domain-modeling"
    "mattpocock-grill-me"
    "mattpocock-grill-with-docs"
    "mattpocock-grilling"
    "mattpocock-handoff"
    "mattpocock-research"
    "mattpocock-resolving-merge-conflicts"
    "mattpocock-setup-matt-pocock-skills"
    "mattpocock-tdd"
    "mattpocock-wizard"
    "mattpocock-writing-for-agents"
  ];
  pstackCodexSkills = [ "pstack-unslop" ];
  appearanceUpdater = pkgs.writers.writePython3Bin "configure-codex-desktop-appearance" {
    libraries = [ pkgs.python3Packages.tomlkit ];
    flakeIgnore = [ "E501" ];
  } ./scripts/configure-codex-desktop-appearance.py;
  appearanceSettings = pkgs.writeText "codex-desktop-appearance.json" (
    builtins.toJSON {
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
    }
  );
  codexDesktopAppearance = writeBashTemplate {
    name = "configure-codex-desktop-appearance";
    src = ./scripts/configure-codex-desktop-appearance.sh.in;
    replacements = {
      shell = lib.getExe pkgs.bash;
      updater = lib.getExe' appearanceUpdater "configure-codex-desktop-appearance";
      inherit appearanceSettings;
      codexConfig = lib.escapeShellArg "${config.xdg.configHome}/codex/config.toml";
    };
  };
in
{
  home.packages = lib.optional supportsRemindctl remindctl;

  # Codex Desktop owns most of this TOML file, including project trust and
  # session preferences.  Update only its native appearance keys instead of
  # replacing the file with a Home Manager-generated configuration.
  home.activation.configureCodexDesktopAppearance = lib.mkIf supportsDesktop (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${lib.getExe pkgs.bash} ${codexDesktopAppearance}
    ''
  );

  programs.codex = {
    enable = true;
    package = pkgs.codex;
    skills =
      lib.optionalAttrs supportsRemindctl { apple-reminders = remindctl.agentSkill; }
      // skillSet mattpocockSkills mattpocockCodexSkills
      // skillSet pstackSkills pstackCodexSkills;
  };
}
