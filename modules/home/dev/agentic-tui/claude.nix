{
  config,
  lib,
  pkgs,
  ...
}:
{
  programs.claude-code.context = lib.mkIf (config.programs.dev-worktree.enable or false) (
    lib.mkAfter config.programs.dev-worktree.instructions
  );

  programs.claude-code = {
    enable = true;
    package = pkgs.claude-code;
    # Keep existing sessions and settings in their current location.
    configDir = "${config.home.homeDirectory}/.claude";
  };
}
