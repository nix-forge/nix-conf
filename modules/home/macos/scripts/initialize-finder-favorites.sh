# shellcheck shell=bash
if [[ ! -e @lib_escapeShellArg_initializedMarker@ ]]; then
  run @lib_escapeShellArg_executable@ apply \
    --config @lib_escapeShellArg_configurationFile@ \
    --state-directory @lib_escapeShellArg_stateDirectory@
  run @lib_getExe_pkgs_coreutils_mkdir@ -p -m 0700 \
    @lib_escapeShellArg_stateDirectory@
  run @lib_getExe_pkgs_coreutils_touch@ \
    @lib_escapeShellArg_initializedMarker@
fi
