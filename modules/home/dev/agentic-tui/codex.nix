{
  config,
  lib,
  pkgs,
  self,
  system,
  ...
}:
let
  supportsRemindctl = self.packages.${system} ? remindctl;
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
    "mattpocock-pr"
    "mattpocock-research"
    "mattpocock-setup-matt-pocock-skills"
    "mattpocock-tdd"
    "mattpocock-wizard"
    "mattpocock-writing-for-agents"
  ];
  pstackCodexSkills = [ "pstack-unslop" ];
in
{
  imports = [ ./codex-home.nix ];

  # Terminal Codex needs the same Linux sandbox helper as the desktop app.
  home.packages =
    lib.optional supportsRemindctl remindctl
    ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.bubblewrap ];

  programs.codex.context = lib.mkIf (config.programs.dev-worktree.enable or false) (
    lib.mkAfter config.programs.dev-worktree.instructions
  );

  programs.codex = {
    enable = true;
    skills =
      lib.optionalAttrs supportsRemindctl { apple-reminders = remindctl.agentSkill; }
      // skillSet mattpocockSkills mattpocockCodexSkills
      // skillSet pstackSkills pstackCodexSkills;
  };
}
