{ config, lib, ... }: {
  programs.opencode = {
    enable = true;
    settings.worktree.directory = lib.mkIf (config.programs.dev-worktree.enable or false) (
      lib.mkDefault "${config.programs.dev-worktree.worktreeRoot}/opencode"
    );
  };
}
