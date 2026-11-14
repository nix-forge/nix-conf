# shellcheck shell=bash
if [[ ! -f @lib_escapeShellArg_stagedConfigFile@ ]] ||
  ! /usr/bin/cmp -s \
    @lib_escapeShellArg_cfg_settingsFile@ \
    @lib_escapeShellArg_stagedConfigFile@; then
  run /bin/mkdir -p @lib_escapeShellArg_stagedConfigDirectory@
  run /usr/bin/install -m 0600 \
    @lib_escapeShellArg_cfg_settingsFile@ \
    @lib_escapeShellArg_stagedConfigFile_tmp@
  run /bin/mv -f \
    @lib_escapeShellArg_stagedConfigFile_tmp@ \
    @lib_escapeShellArg_stagedConfigFile@
fi
