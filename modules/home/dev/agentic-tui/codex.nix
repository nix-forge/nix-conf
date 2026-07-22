{
  lib,
  pkgs,
  self,
  system,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin isAarch64;
  supportsRemindctl = isDarwin && isAarch64;
  remindctl = self.packages.${system}.remindctl;
  anthropicSkills = self.packages.${system}.anthropic-skills;
  openaiSkills = self.packages.${system}.openai-skills;
  skillPath = package: name: "${package}/share/agent-skills/${name}";
  skillSet = package: names: lib.genAttrs names (name: skillPath package name);

  anthropicCodexSkills = [
    "anthropic-algorithmic-art"
    "anthropic-frontend-design"
    "anthropic-webapp-testing"
  ];
  openaiCodexSkills = [
    "openai-chatgpt-apps"
    "openai-define-goal"
    "openai-playwright"
    "openai-playwright-interactive"
    "openai-screenshot"
  ];
in
{
  home.packages = lib.optional supportsRemindctl remindctl;

  programs.codex = {
    enable = true;
    package = pkgs.codex;
    skills =
      lib.optionalAttrs supportsRemindctl { apple-reminders = remindctl.agentSkill; }
      // skillSet anthropicSkills anthropicCodexSkills
      // skillSet openaiSkills openaiCodexSkills;
  };
}
