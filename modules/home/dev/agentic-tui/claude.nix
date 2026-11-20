{
  config,
  lib,
  pkgs,
  ...
}:
{
  programs.claude-code = {
    enable = true;
    package = pkgs.claude-code;
    configDir = "${config.home.homeDirectory}/.claude";
    # Native desktop SSH setting; CLI worktrees keep Claude's own lifecycle.
    settings.worktree.location = lib.mkIf (config.programs.dev-worktree.enable or false) (
      lib.mkDefault "${config.programs.dev-worktree.worktreeRoot}/claude"
    );
  };
}
