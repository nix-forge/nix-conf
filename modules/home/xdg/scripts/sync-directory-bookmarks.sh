# shellcheck shell=bash
# Sourced by Home Manager or the owning build phase.
run @lib_getExe_command@ \
  --config @lib_escapeShellArg_toString_policy@ \
  --home @lib_escapeShellArg_config_home_homeDirectory@ \
  --config-home @lib_escapeShellArg_config_xdg_configHome@ \
  --data-home @lib_escapeShellArg_config_xdg_dataHome@
