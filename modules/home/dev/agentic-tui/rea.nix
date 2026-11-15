{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs) rea;
  skill = pkgs.runCommand "rea-on-demand-skill" { } ''
    mkdir -p "$out"
    cp -R ${rea.skills}/share/agent-skills/reverse-engineer-anything/. "$out/"
    chmod u+w "$out/SKILL.md"
    substituteInPlace "$out/SKILL.md" --replace-fail '# REA' \
      ${lib.escapeShellArg ("# REA\n\n" + builtins.readFile ./rea-lifecycle.md)}
  '';
in
{
  home.packages = [ rea ];

  programs = {
    mcp.enable = true;

    codex = lib.mkIf config.programs.codex.enable {
      # The desktop settings reconciler owns Codex's writable config.toml.
      enableMcpIntegration = false;
      skills.reverse-engineer-anything = skill;
    };

    claude-code = lib.mkIf config.programs.claude-code.enable {
      enableMcpIntegration = true;
      skills.reverse-engineer-anything = skill;
    };

    opencode = lib.mkIf config.programs.opencode.enable {
      enableMcpIntegration = true;
      skills.reverse-engineer-anything = skill;
    };
  };
}
