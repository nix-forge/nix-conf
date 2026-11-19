# shellcheck shell=bash
# Sourced by Home Manager or the owning build phase.
run @lib_getExe_pkgs_coreutils_mkdir@ -p -- @lib_escapeShellArg_cfg_developerRoot@
if @worktree_mount_check@; then
  run @lib_getExe_pkgs_coreutils_mkdir@ -p -- \
    @lib_escapeShellArg_cfg_worktreeRoot_manual@ \
    @lib_escapeShellArg_cfg_worktreeRoot_codex@ \
    @lib_escapeShellArg_cfg_worktreeRoot_claude@
fi
run @lib_getExe_pkgs_coreutils_mkdir@ -p -m 700 -- @lib_escapeShellArg_cfg_stateDirectory@
