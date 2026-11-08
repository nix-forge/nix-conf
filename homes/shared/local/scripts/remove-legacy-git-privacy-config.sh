# shellcheck shell=bash
bootstrap=@lib_escapeShellArg_config_xdg_stateHome_git_privacy_bootstra@
global_config=@lib_escapeShellArg_config_home_homeDirectory_gitconfig@
if test -f "$global_config" && @lib_getExe_pkgs_git_git@ config --file "$global_config" \
  --fixed-value --get-all include.path "$bootstrap" >/dev/null; then
  run @lib_getExe_pkgs_git_git@ config --file "$global_config" \
    --fixed-value --unset-all include.path "$bootstrap"
fi
run @lib_getExe_pkgs_coreutils_rm@ -f -- \
  @lib_escapeShellArg_config_xdg_configHome_jj_conf_d_99_git_pr@
