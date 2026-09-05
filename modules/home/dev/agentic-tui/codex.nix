{
  lib,
  pkgs,
  self,
  system,
  config,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin isAarch64;
  supportsRemindctl = isDarwin && isAarch64;
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
  codexDesktopAppearance = pkgs.replaceVarsWith {
    name = "configure-codex-desktop-appearance";
    src = ./scripts/configure-codex-desktop-appearance.sh.in;
    replacements = {
      shell = lib.getExe pkgs.bash;
      mkdir = lib.getExe' pkgs.coreutils "mkdir";
      dirname = lib.getExe' pkgs.coreutils "dirname";
      perl = lib.getExe pkgs.perl;
      codexConfig = lib.escapeShellArg "${config.xdg.configHome}/codex/config.toml";
      appearanceTheme = lib.escapeShellArg "dark";
      surface = lib.escapeShellArg "#${config.appearance.palette.surface}";
      ink = lib.escapeShellArg "#${config.appearance.palette.text}";
      accent = lib.escapeShellArg "#${config.appearance.palette.accent}";
      diffAdded = lib.escapeShellArg "#${config.appearance.palette.diffAdded}";
      diffRemoved = lib.escapeShellArg "#${config.appearance.palette.diffRemoved}";
      skill = lib.escapeShellArg "#${config.appearance.palette.special}";
      uiFont = lib.escapeShellArg config.stylix.fonts.sansSerif.name;
      codeFont = lib.escapeShellArg config.stylix.fonts.monospace.name;
    };
  };
in
{
  home.packages = lib.optional supportsRemindctl remindctl;

  # Codex Desktop owns most of this TOML file, including project trust and
  # session preferences.  Update only its native appearance keys instead of
  # replacing the file with a Home Manager-generated configuration.
  home.activation.configureCodexDesktopAppearance = lib.mkIf supportsRemindctl (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      source ${codexDesktopAppearance}
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
