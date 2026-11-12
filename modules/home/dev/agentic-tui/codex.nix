{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./codex-home.nix
    ./agent-skills.nix
  ];

  # Terminal Codex needs the same Linux sandbox helper as the desktop app.
  home.packages = lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.bubblewrap ];

  programs.codex.context = lib.mkIf (config.programs.dev-worktree.enable or false) (
    lib.mkAfter config.programs.dev-worktree.instructions
  );

  programs.codex = {
    enable = true;
  };
}
