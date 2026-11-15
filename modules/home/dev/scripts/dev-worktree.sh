# shellcheck shell=bash
export DEV_WORKTREE_GIT=@lib_escapeShellArg_lib_getExe_config_programs_git_package@
exec @lib_getExe_implementation@ --config @policy@ "$@"
