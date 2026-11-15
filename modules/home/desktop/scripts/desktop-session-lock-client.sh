# shellcheck shell=bash
exec @pkgs_bash@/bin/bash @scripts_session_lock_sh@ "$@" \
  @lib_getExe_config_programs_hyprlock_package@ \
  --config @lib_escapeShellArg_config_xdg_configHome_hypr_hyprlock_conf@
