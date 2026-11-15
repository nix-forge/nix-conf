# shellcheck shell=bash
# Sourced by Home Manager or the owning build phase.
run @lib_escapeShellArg_executable@ apply \
  --config @lib_escapeShellArg_configurationFile@ \
  --state-directory @lib_escapeShellArg_stateDirectory@
